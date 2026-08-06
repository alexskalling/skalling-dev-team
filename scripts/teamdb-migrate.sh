#!/usr/bin/env bash
# teamdb-migrate.sh — Migra .jsonl/.md legacy a teamdb (preserva .md, DC-1)
# T-2.8: Solo .jsonl se mueve a legacy/. .md se conserva como export legible.
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SKALLING_ROOT_DIR="$(dirname "$SCRIPT_DIR")"
export SKALLING_ROOT="$SKALLING_ROOT_DIR"
if [ -f "$SCRIPT_DIR/lib-teamdb.sh" ]; then
  # shellcheck disable=SC1091
  source "$SCRIPT_DIR/lib-teamdb.sh"
elif [ -f "$SCRIPT_DIR/lib/lib-teamdb.sh" ]; then
  # shellcheck disable=SC1091
  source "$SCRIPT_DIR/lib/lib-teamdb.sh"
else
  echo "ERROR: lib-teamdb.sh no encontrado" >&2
  exit 1
fi

DRY_RUN=false
while [[ $# -gt 0 ]]; do
  case "$1" in
    --dry-run) DRY_RUN=true; shift ;;
    *) PROJECT="$1"; shift ;;
  esac
done
PROJECT="${PROJECT:-$(pwd)}"
teamdb_init_project "$PROJECT"
local_db="$(teamdb_project_path "$PROJECT")"

_run_sql() {
  if [ "$DRY_RUN" = true ]; then
    echo "    [dry-run] sqlite3 $local_db < $1"
  else
    sqlite3 "$local_db" < "$1" 2>/dev/null || true
  fi
}
CTX_DIR="$PROJECT/.opencode/context"

sql_escape() {
  printf '%s' "$1" | sed "s/'/''/g"
}

json_field() {
  local field="$1"
  python3 -c "import json,sys; d=json.loads(sys.stdin.read()); print(d.get('$field',''))" 2>/dev/null || echo ""
}

# Detectar si hay .jsonl
JSONL_FOUND=0
for _ignore in "$CTX_DIR"/*.jsonl; do
  [ -e "$_ignore" ] && JSONL_FOUND=1 && break
done

# Migrar .jsonl a tablas, luego mover a legacy
if [ "$JSONL_FOUND" = "1" ]; then
  for jsonl in "$CTX_DIR"/*.jsonl; do
    [ -e "$jsonl" ] || continue
    fname=$(basename "$jsonl" .jsonl)
    case "$fname" in
      DECISIONS)
        while IFS= read -r line; do
          [ -n "$line" ] || continue
          topic=$(echo "$line" | json_field "topic") || continue
          decision=$(echo "$line" | json_field "decision") || continue
          [ -n "$topic" ] || continue
          topic_e=$(sql_escape "$topic")
          decision_e=$(sql_escape "$decision")
          teamdb_exec_write "$local_db" \
            "INSERT OR IGNORE INTO decisions(slug, title, body_md, status, decided_at, decided_by) VALUES(?, ?, ?, 'accepted', datetime('now'), 'migrated')" \
            "$topic_e" "$topic_e" "$decision_e" >/dev/null 2>&1 || true
        done < "$jsonl"
        ;;
      PATTERNS|PROJECT)
        while IFS= read -r line; do
          [ -n "$line" ] || continue
          name=$(echo "$line" | python3 -c "import sys,json; d=json.loads(sys.stdin.read()); print(d.get('name') or d.get('key',''))" 2>/dev/null) || continue
          desc=$(echo "$line" | python3 -c "import sys,json; d=json.loads(sys.stdin.read()); print(d.get('description') or d.get('value') or d.get('note',''))" 2>/dev/null) || continue
          [ -n "$name" ] || continue
          name_e=$(sql_escape "$name")
          desc_e=$(sql_escape "$desc")
          teamdb_exec_write "$local_db" \
            "INSERT OR IGNORE INTO concepts(slug, title, body_md, category, updated_at) VALUES(?, ?, ?, 'legacy', datetime('now'))" \
            "$name_e" "$name_e" "$desc_e" >/dev/null 2>&1 || true
        done < "$jsonl"
        ;;
      PREFERENCES)
        while IFS= read -r line; do
          [ -n "$line" ] || continue
          slug=$(echo "$line" | python3 -c "import sys,json; d=json.loads(sys.stdin.read()); print(d.get('slug') or d.get('scope',''))" 2>/dev/null) || continue
          body=$(echo "$line" | json_field "preference") || continue
          [ -n "$slug" ] || continue
          slug_e=$(sql_escape "$slug")
          body_e=$(sql_escape "$body")
          teamdb_exec_write "$local_db" \
            "INSERT OR IGNORE INTO preferences(slug, scope, body_md, source) VALUES(?, 'legacy', ?, 'migrated')" \
            "$slug_e" "$body_e" >/dev/null 2>&1 || true
        done < "$jsonl"
        ;;
      REJECTIONS)
        while IFS= read -r line; do
          [ -n "$line" ] || continue
          attempted=$(json_field "attempted" <<< "$line") || continue
          reason=$(json_field "reason" <<< "$line") || continue
          [ -n "$attempted" ] || continue
          attempted_e=$(sql_escape "$attempted")
          reason_e=$(sql_escape "$reason")
          teamdb_exec_write "$local_db" \
            "INSERT OR IGNORE INTO known_problems(slug, title, symptom_md, status, discovered_at) VALUES(?, ?, ?, 'open', datetime('now'))" \
            "$attempted_e" "$attempted_e" "$reason_e" >/dev/null 2>&1 || true
        done < "$jsonl"
        ;;
    esac
  done

  # Mover SOLO .jsonl a legacy
  LEGACY="$CTX_DIR/legacy"
  mkdir -p "$LEGACY"
  mv "$CTX_DIR"/*.jsonl "$LEGACY/" 2>/dev/null || true
fi

# Migrar .md de concepts: frontmatter → metadata, body → body_md
# DC-1: NO mover .md a legacy
if [ -d "$CTX_DIR/concept" ]; then
  for md in "$CTX_DIR/concept/"*.md; do
    [ -e "$md" ] || continue
    fname=$(basename "$md" .md)
    # Extraer frontmatter
    in_fm=0
    fm_done=0
    body=""
    type_v=""
    confidence_v="0.8"
    while IFS= read -r mline; do
      if [ "$fm_done" = "0" ]; then
        if [ "$in_fm" = "0" ]; then
          if [ "$mline" = "---" ]; then
            in_fm=1
            continue
          fi
          # No frontmatter: linea es parte del body
          body="${body}${mline}
"
        else
          if [ "$mline" = "---" ]; then
            in_fm=0
            fm_done=1
            continue
          fi
          case "$mline" in
            type:*) type_v="${mline#type:}"
                     type_v="$(printf '%s' "$type_v" | sed 's/^[[:space:]]*//;s/[[:space:]]*$//' | tr '[:upper:]' '[:lower:]')" ;;
            confidence:*) confidence_v="${mline#confidence:}"
                            confidence_v="$(printf '%s' "$confidence_v" | sed 's/^[[:space:]]*//;s/[[:space:]]*$//')" ;;
          esac
        fi
      else
        body="${body}${mline}
"
      fi
    done < "$md"
    [ -z "$type_v" ] && type_v="concept"
    fname_e=$(sql_escape "$fname")
    body_e=$(sql_escape "$body")
    type_e=$(sql_escape "$type_v")
    # shellcheck disable=SC2034
    conf_e=$(sql_escape "$confidence_v")
    teamdb_exec_write "$local_db" \
      "INSERT OR IGNORE INTO concepts(slug, title, body_md, category, updated_at) VALUES(?, ?, ?, ?, datetime('now'))" \
      "$fname_e" "$fname_e" "$body_e" "$type_e" >/dev/null 2>&1 || true
    # confidence se ignora por ahora (T-3.x podria mapearlo a columna nueva)
  done
fi

# Si no hay NADA que migrar
if [ "$JSONL_FOUND" = "0" ] && [ ! -d "$CTX_DIR/concept" ]; then
  echo "[WARN] no legacy .jsonl or .md concept files to migrate" >&2
fi

echo "migrated: $local_db"
