#!/usr/bin/env bash
# migrate-legacy-md-to-db.sh — Migra .md legacy de .opencode/context/ a team.db
#
# Idempotente: usa INSERT OR IGNORE sobre UNIQUE slugs. Re-ejecutable.
# Conservador: NUNCA borra .md legacy (quedan como backup legible).
#
# Mapea:
#   concept/*.md           → concepts
#   decisiones/*.md        → decisions
#   followups/*.md         → work_in_progress (type='plan', status='open')
#   preferencias/*.md      → preferences
#   problemas-conocidos/*.md → known_problems
#
# Uso:
#   bash scripts/migrate-legacy-md-to-db.sh           # migra
#   bash scripts/migrate-legacy-md-to-db.sh --dry-run # muestra qué haría

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(git -C "$SCRIPT_DIR" rev-parse --show-toplevel 2>/dev/null || pwd)"
DB="$PROJECT_DIR/.opencode/context/team.db"
CONTEXT="$PROJECT_DIR/.opencode/context"

DRY_RUN=false
[[ "${1:-}" == "--dry-run" ]] && DRY_RUN=true

# ────────────────────────────────────────────────────────────────────────────
# Helpers
# ────────────────────────────────────────────────────────────────────────────

if [[ ! -f "$DB" ]]; then
  printf 'ERROR: DB no encontrada en %s\n' "$DB" >&2
  exit 1
fi

if ! command -v sqlite3 >/dev/null 2>&1; then
  printf 'ERROR: sqlite3 no instalado\n' >&2
  exit 1
fi

# Lee un archivo .md y devuelve (frontmatter_as_kv_pairs, body_md).
# Usa awk — sin dependencias de yq/jq/python.
parse_md() {
  local file="$1"
  awk '
    BEGIN { infm=0; inbody=0 }
    /^---$/ {
      if (infm == 0) { infm = 1; next }
      else if (infm == 1) { infm = 0; inbody = 1; next }
    }
    infm == 1 { print "FM|" $0; next }
    inbody == 1 { print "BD|" $0; next }
  ' "$file"
}

# Extrae un valor del frontmatter parseado.
# Uso: printf '%s\n' "$parsed" | fm_get <key>
fm_get() {
  local key="$1"
  awk -F'|' -v k="$key" '
    /^[ ]*FM\|/ {
      line = substr($0, length("FM|") + 1)
      n = index(line, ":")
      if (n > 0) {
        k2 = tolower(substr(line, 1, n - 1))
        gsub(/^[ \t]+|[ \t]+$/, "", k2)
        if (k2 == k) {
          v = substr(line, n + 1)
          gsub(/^[ \t]+|[ \t]+$/, "", v)
          print v
          exit
        }
      }
    }
  '
}

# Lee el body de un archivo .md. Si tiene frontmatter (---), lo salta; si no,
# devuelve el archivo entero.
body_get() {
  local file="$1"
  awk '
    NR == 1 && /^---$/ { in_fm = 1; next }
    in_fm == 1 && /^---$/ { in_fm = 0; next }
    !in_fm { print }
  ' "$file"
}

# Lee el primer heading (# ...) de un archivo, sin el "#".
# Si no hay heading, devuelve el nombre del archivo sin extensión.
heading_title() {
  local file="$1"
  local default="$2"
  local title
  title="$(awk '/^#[ \t]+/ { sub(/^#[ \t]+/, ""); print; exit }' "$file")"
  if [[ -n "$title" ]]; then
    printf '%s\n' "$title"
  else
    printf '%s\n' "$default"
  fi
}

# Escapa comillas simples para SQL ('' es el escape estándar de SQLite).
sql_esc() {
  printf '%s' "$1" | sed "s/'/''/g"
}

run_sql() {
  local sql="$1"
  if $DRY_RUN; then
    printf '[dry-run] %s\n' "$sql"
  else
    sqlite3 "$DB" "$sql"
  fi
}

# ────────────────────────────────────────────────────────────────────────────
# Migración
# ────────────────────────────────────────────────────────────────────────────

migrated=0
skipped=0

# ── concepts ──
printf '─── concepts ───\n'
while IFS= read -r -d '' file; do
  parsed="$(parse_md "$file")"
  slug="$(printf '%s' "$parsed" | fm_get slug || true)"
  if [[ -z "$slug" ]]; then
    slug="$(basename "$file" .md)"
  fi
  title="$(printf '%s' "$parsed" | fm_get title || true)"
  if [[ -z "$title" ]]; then
    title="$(basename "$file" .md)"
  fi
  category="$(printf '%s' "$parsed" | fm_get category || true)"
  [[ -z "$category" ]] && category="$(basename "$(dirname "$file")")"
  updated_at="$(printf '%s' "$parsed" | fm_get timestamp || date -u +%Y-%m-%dT%H:%M:%SZ)"
  body="$(body_get "$file")"

  run_sql "INSERT OR IGNORE INTO concepts (slug, title, body_md, category, updated_at) VALUES ('$(sql_esc "$slug")', '$(sql_esc "$title")', '$(sql_esc "$body")', '$(sql_esc "$category")', '$(sql_esc "$updated_at")');"
  migrated=$((migrated + 1))
done < <(find "$CONTEXT/concept" -maxdepth 1 -name "*.md" -type f -print0 2>/dev/null)

# ── decisions ──
printf '─── decisions ───\n'
while IFS= read -r -d '' file; do
  parsed="$(parse_md "$file")"
  slug="$(printf '%s' "$parsed" | fm_get slug || true)"
  if [[ -z "$slug" ]]; then
    slug="$(basename "$file" .md)"
  fi
  title="$(printf '%s' "$parsed" | fm_get title || true)"
  [[ -z "$title" ]] && title="$(basename "$file" .md)"
  status="$(printf '%s' "$parsed" | fm_get status || echo 'accepted')"
  decided_at="$(printf '%s' "$parsed" | fm_get decided_at || printf '%s' "$parsed" | fm_get date || true)"
  decided_by="$(printf '%s' "$parsed" | fm_get decided_by || printf '%s' "$parsed" | fm_get agent || true)"
  body="$(body_get "$file")"

  run_sql "INSERT OR IGNORE INTO decisions (slug, title, body_md, status, decided_at, decided_by) VALUES ('$(sql_esc "$slug")', '$(sql_esc "$title")', '$(sql_esc "$body")', '$(sql_esc "$status")', '$(sql_esc "$decided_at")', '$(sql_esc "$decided_by")');"
  migrated=$((migrated + 1))
done < <(find "$CONTEXT/decisiones" -maxdepth 1 -name "*.md" -type f -print0 2>/dev/null)

# ── work_in_progress ──
printf '─── work_in_progress ───\n'
while IFS= read -r -d '' file; do
  parsed="$(parse_md "$file")"
  slug="$(printf '%s' "$parsed" | fm_get slug || true)"
  [[ -z "$slug" ]] && slug="followup-$(basename "$file" .md)"
  title="$(printf '%s' "$parsed" | fm_get title || true)"
  [[ -z "$title" ]] && title="$(heading_title "$file" "Follow-ups $(basename "$file" .md)")"
  body="$(body_get "$file")"
  desc="$(printf '%s' "$body" | head -c 200)"
  now="$(date -u +%Y-%m-%dT%H:%M:%SZ)"

  run_sql "INSERT OR IGNORE INTO work_in_progress (slug, type, title, description, status, priority, body_md, created_at, updated_at) VALUES ('$(sql_esc "$slug")', 'plan', '$(sql_esc "$title")', '$(sql_esc "$desc")', 'open', 3, '$(sql_esc "$body")', '$now', '$now');"
  migrated=$((migrated + 1))
done < <(find "$CONTEXT/followups" -maxdepth 1 -name "*.md" -type f -print0 2>/dev/null)

# ── preferences ──
printf '─── preferences ───\n'
while IFS= read -r -d '' file; do
  parsed="$(parse_md "$file")"
  slug="$(printf '%s' "$parsed" | fm_get slug || true)"
  [[ -z "$slug" ]] && slug="$(basename "$file" .md)"
  body="$(body_get "$file")"
  confidence="$(printf '%s' "$parsed" | fm_get confidence || echo '0.9')"
  source="$(printf '%s' "$parsed" | fm_get type || echo 'preference')"

  run_sql "INSERT OR IGNORE INTO preferences (slug, scope, body_md, confidence, source) VALUES ('$(sql_esc "$slug")', 'project', '$(sql_esc "$body")', '$confidence', '$(sql_esc "$source")');"
  migrated=$((migrated + 1))
done < <(find "$CONTEXT/preferencias" -maxdepth 1 -name "*.md" -type f -print0 2>/dev/null)

# ── known_problems ──
printf '─── known_problems ───\n'
while IFS= read -r -d '' file; do
  parsed="$(parse_md "$file")"
  slug="$(printf '%s' "$parsed" | fm_get slug || true)"
  [[ -z "$slug" ]] && slug="$(basename "$file" .md)"
  title="$(printf '%s' "$parsed" | fm_get title || true)"
  [[ -z "$title" ]] && title="$(heading_title "$file" "$(basename "$file" .md)")"
  status="$(printf '%s' "$parsed" | fm_get status || echo 'open')"
  # known_problems solo acepta: open|monitoring|resolved|wontfix
  case "$status" in
    open|monitoring|resolved|wontfix) ;;
    *) status='open' ;;
  esac
  discovered_at="$(printf '%s' "$parsed" | fm_get discovered_at || true)"
  symptom="$(body_get "$file")"
  workaround="$(printf '%s' "$parsed" | fm_get workaround_md || true)"

  run_sql "INSERT OR IGNORE INTO known_problems (slug, title, symptom_md, workaround_md, status, discovered_at) VALUES ('$(sql_esc "$slug")', '$(sql_esc "$title")', '$(sql_esc "$symptom")', '$(sql_esc "$workaround")', '$(sql_esc "$status")', '$(sql_esc "$discovered_at")');"
  migrated=$((migrated + 1))
done < <(find "$CONTEXT/problemas-conocidos" -maxdepth 1 -name "*.md" -type f -print0 2>/dev/null)

# ── resumen ──
printf '\n─── resultado ───\n'
printf 'migrated (intentados): %d\n' "$migrated"
if ! $DRY_RUN; then
  printf '\nEstado actual:\n'
  for t in concepts decisions work_in_progress preferences known_problems; do
    count="$(sqlite3 "$DB" "SELECT COUNT(*) FROM $t" 2>/dev/null)"
    printf '  %-22s %s rows\n' "$t" "$count"
  done
fi