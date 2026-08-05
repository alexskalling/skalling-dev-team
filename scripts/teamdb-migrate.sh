#!/usr/bin/env bash
# teamdb-migrate.sh — Migra .jsonl/.md legacy a teamdb (SQL-injection safe)
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
export SKALLING_ROOT="$(dirname "$SCRIPT_DIR")"
source "$SCRIPT_DIR/lib/lib-teamdb.sh"

PROJECT="${1:-$(pwd)}"
teamdb_init_project "$PROJECT"
local_db="$(teamdb_project_path "$PROJECT")"
CTX_DIR="$PROJECT/.opencode/context"

# Helper: escape single quotes for SQL (seguro para interpolación en strings SQL)
sql_escape() {
  echo "$1" | sed "s/'/''/g"
}

# Helper: parse JSON field safely (lee stdin como JSON line)
json_field() {
  local field="$1"
  python3 -c "import json,sys; d=json.loads(sys.stdin.read()); print(d.get('$field',''))" 2>/dev/null || echo ""
}

# Migrar .jsonl
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
        topic=$(sql_escape "$topic")
        decision=$(sql_escape "$decision")
        teamdb_write_project "$local_db" "INSERT OR IGNORE INTO decisions (slug, title, body_md, decided_at) VALUES ('$topic', '$topic', '$decision', datetime('now'))"
      done < "$jsonl"
      ;;
    PATTERNS|PROJECT)
      while IFS= read -r line; do
        [ -n "$line" ] || continue
        name=$(echo "$line" | python3 -c "import sys,json; d=json.loads(sys.stdin.read()); print(d.get('name') or d.get('key',''))" 2>/dev/null) || continue
        desc=$(echo "$line" | python3 -c "import sys,json; d=json.loads(sys.stdin.read()); print(d.get('description') or d.get('value') or d.get('note',''))" 2>/dev/null) || continue
        [ -n "$name" ] || continue
        name=$(sql_escape "$name")
        desc=$(sql_escape "$desc")
        teamdb_write_project "$local_db" "INSERT OR IGNORE INTO concepts (slug, title, body_md, category, updated_at) VALUES ('$name', '$name', '$desc', 'legacy', datetime('now'))"
      done < "$jsonl"
      ;;
    PREFERENCES)
      while IFS= read -r line; do
        [ -n "$line" ] || continue
        slug=$(echo "$line" | python3 -c "import sys,json; d=json.loads(sys.stdin.read()); print(d.get('slug') or d.get('scope',''))" 2>/dev/null) || continue
        body=$(echo "$line" | json_field "preference") || continue
        [ -n "$slug" ] || continue
        slug=$(sql_escape "$slug")
        body=$(sql_escape "$body")
        teamdb_write_project "$local_db" "INSERT OR IGNORE INTO preferences (slug, scope, body_md, source) VALUES ('$slug', 'legacy', '$body', 'migrated')"
      done < "$jsonl"
      ;;
    REJECTIONS)
      while IFS= read -r line; do
        [ -n "$line" ] || continue
        attempted=$(json_field "attempted" <<< "$line") || continue
        reason=$(json_field "reason" <<< "$line") || continue
        [ -n "$attempted" ] || continue
        attempted=$(sql_escape "$attempted")
        reason=$(sql_escape "$reason")
        teamdb_write_project "$local_db" "INSERT OR IGNORE INTO known_problems (slug, title, symptom_md, discovered_at) VALUES ('$attempted', '$attempted', '$reason', datetime('now'))"
      done < "$jsonl"
      ;;
  esac
done

# Migrar .md de concepts
if [ -d "$CTX_DIR/concept" ]; then
  for md in "$CTX_DIR/concept/"*.md; do
    [ -e "$md" ] || continue
    fname=$(basename "$md" .md)
    body=$(cat "$md" | sed "s/'/''/g")
    fname=$(sql_escape "$fname")
    teamdb_write_project "$local_db" "INSERT OR IGNORE INTO concepts (slug, title, body_md, category, updated_at) VALUES ('$fname', '$fname', '$body', 'concept', datetime('now'))"
  done
fi

# Mover legacy
LEGACY="$CTX_DIR/legacy"
mkdir -p "$LEGACY"
[ -d "$CTX_DIR/concept" ] && mv "$CTX_DIR/concept" "$LEGACY/" 2>/dev/null || true
[ -d "$CTX_DIR/decisiones" ] && mv "$CTX_DIR/decisiones" "$LEGACY/" 2>/dev/null || true
mv "$CTX_DIR"/*.jsonl "$LEGACY/" 2>/dev/null || true

echo "migrated: $local_db"
