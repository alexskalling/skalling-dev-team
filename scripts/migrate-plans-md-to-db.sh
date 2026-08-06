#!/usr/bin/env bash
# migrate-plans-md-to-db.sh — Migra archivos .md de planes viejos a la DB
# Lee: docs/plans/*.md (legacy original) y .opencode/changes/*/proposal.md
# Inserta en la tabla `proposals` con decided_by='legacy-import' y slug
# derivado del path (con sufijo -legacy-imported para evitar colisiones).
#
# Uso: migrate-plans-md-to-db.sh [--dry-run] [<project>]
#   --dry-run   solo lista los archivos que migraría, sin tocar la DB
#   <project>   ruta al proyecto (default: cwd)
#
# INVARIANTE: idempotente — si el slug ya existe, lo salta.
# SEGURIDAD: usa teamdb_exec_write con parameter binding (R10).

set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# shellcheck disable=SC1091
if [ -f "$SCRIPT_DIR/lib-teamdb.sh" ]; then
  source "$SCRIPT_DIR/lib-teamdb.sh"
elif [ -f "$SCRIPT_DIR/lib/lib-teamdb.sh" ]; then
  source "$SCRIPT_DIR/lib/lib-teamdb.sh"
else
  echo "ERROR: lib-teamdb.sh no encontrado" >&2
  exit 1
fi

DRY_RUN=false
PROJECT="$(pwd)"
while [[ $# -gt 0 ]]; do
  case "$1" in
    --dry-run) DRY_RUN=true; shift ;;
    -h|--help)
      sed -n '2,12p' "$0" | sed 's/^# *//'
      exit 0
      ;;
    *) PROJECT="$1"; shift ;;
  esac
done

DB="$(teamdb_project_path "$PROJECT")"
if [ ! -f "$DB" ]; then
  echo "ERROR: DB no existe en $PROJECT (esperado: $DB)" >&2
  exit 1
fi

# Backup de la DB antes de mutar (solo si NO es dry-run)
if [ "$DRY_RUN" = false ]; then
  BACKUP="$DB.pre-migration-md-to-db.$(date +%Y%m%d-%H%M%S)"
  cp "$DB" "$BACKUP"
  echo "✓ Backup DB: $BACKUP"
fi

# Detectar archivos .md de planes
md_files=()

# 1) docs/plans/*.md (legacy original)
if [ -d "$PROJECT/docs/plans" ]; then
  shopt -s nullglob
  for f in "$PROJECT"/docs/plans/*.md; do
    [ -f "$f" ] && md_files+=("$f")
  done
fi

# 2) .opencode/changes/*/proposal.md
if [ -d "$PROJECT/.opencode/changes" ]; then
  for d in "$PROJECT/.opencode/changes"/*/; do
    [ -d "$d" ] || continue
    if [ -f "$d/proposal.md" ]; then
      md_files+=("$d/proposal.md")
    fi
  done
fi

if [ "${#md_files[@]}" -eq 0 ]; then
  echo "No .md files found to migrate"
  exit 0
fi

DRY_TAG=""
[ "$DRY_RUN" = true ] && DRY_TAG=" (dry-run)"
echo "Found ${#md_files[@]} files to migrate${DRY_TAG}"
echo ""

# Función: extraer título, status, agent, y slug desde un .md
# Devuelve: title|status|agent|slug  (separados por tab, para leer en bash)
parse_md() {
  local file="$1"
  python3 - "$file" <<'PYEOF'
import re, sys, os
p = sys.argv[1]
with open(p, encoding='utf-8') as f:
    content = f.read()

# Frontmatter
title = None
status = 'draft'
agent = 'pol'
fm_match = re.search(r'^---\s*\n(.*?)\n---\s*\n', content, re.DOTALL)
if fm_match:
    fm = fm_match.group(1)
    for line in fm.split('\n'):
        m = re.match(r'^title:\s*(.+?)\s*$', line)
        if m: title = m.group(1).strip().strip('"\'')
        m = re.match(r'^status:\s*(.+?)\s*$', line)
        if m: status = m.group(1).strip()
        m = re.match(r'^agent:\s*(.+?)\s*$', line)
        if m: agent = m.group(1).strip()

# Si no hay frontmatter title, buscar primer # heading
if not title:
    m = re.search(r'^#\s+(.+?)\s*$', content, re.MULTILINE)
    if m: title = m.group(1).strip()

# Slug: si el archivo es proposal.md/design.md/tasks.md, usar el directorio padre
base = os.path.basename(p)
if base.endswith('.md'):
    base = base[:-3]
parent = os.path.basename(os.path.dirname(p))
# Si el filename es genérico (proposal/design/tasks), usar el directorio
if base in ('proposal', 'design', 'tasks'):
    base = parent
slug = re.sub(r'^\d{4}-\d{2}-\d{2}-', '', base)
slug = re.sub(r'[^a-z0-9-]+', '-', slug.lower()).strip('-')
if not slug:
    slug = 'unknown'

print(f"{title or slug}\t{status}\t{agent}\t{slug}")
PYEOF
}

# Función: INSERT en proposals con parameter binding (R10 seguro)
insert_proposal() {
  local slug="$1" title="$2" status="$3" agent="$4" intent="$5"
  if [ "$DRY_RUN" = true ]; then
    echo "  [dry-run] would INSERT: slug='$slug' status='$status' agent='$agent' title='$title' (intent_md: ${#intent} bytes)"
    return 0
  fi

  local now; now="$(date -u +%Y-%m-%dT%H:%M:%SZ)"
  # teamdb_exec_write <db> <sql> <param>... — params como positional
  teamdb_exec_write "$DB" \
    "INSERT INTO proposals (slug, title, intent_md, status, agent, decided_by, created_at, updated_at) VALUES (?, ?, ?, ?, ?, 'legacy-import', ?, ?)" \
    "$slug" "$title" "$intent" "$status" "$agent" "$now" "$now"
}

count=0
skipped=0
for f in "${md_files[@]}"; do
  # Parsear título/status/agent/slug
  parsed="$(parse_md "$f")"
  title="$(printf '%s' "$parsed" | cut -f1)"
  status="$(printf '%s' "$parsed" | cut -f2)"
  agent="$(printf '%s' "$parsed" | cut -f3)"
  base_slug="$(printf '%s' "$parsed" | cut -f4)"

  # Sufijo legacy para evitar colisiones con proposals ya en la DB
  slug_imported="${base_slug}-legacy-imported"

  # Verificar si ya existe
  existing="$(sqlite3 "$DB" "SELECT COUNT(*) FROM proposals WHERE slug='$slug_imported'" 2>/dev/null || echo "0")"
  if [ "$existing" != "0" ]; then
    echo "  SKIP: $f → $slug_imported (ya existe)"
    skipped=$((skipped + 1))
    continue
  fi

  # Leer contenido completo (intent_md)
  content="$(cat "$f")"

  # Relativo a PROJECT para mensaje más limpio
  rel="${f#$PROJECT/}"
  echo "  Migrate: $rel → proposals(slug=$slug_imported, status=$status, agent=$agent)"

  if insert_proposal "$slug_imported" "$title" "$status" "$agent" "$content"; then
    count=$((count + 1))
  else
    echo "  ERROR: falló INSERT para $slug_imported" >&2
  fi
done

echo ""
echo "✓ Migrated $count file(s)${DRY_TAG}"
if [ "$skipped" -gt 0 ]; then
  echo "  Skipped $skipped (ya existían)"
fi
