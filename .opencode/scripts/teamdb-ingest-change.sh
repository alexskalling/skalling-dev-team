#!/usr/bin/env bash
# teamdb-ingest-change.sh — Ingiere un change dir de .opencode/changes/<slug>/
# hacia las tablas proposals / plans / tasks / specs de TeamDB.
#
# Uso: teamdb-ingest-change.sh <project> <change-dir> [--dry-run] [--force]
#
# <change-dir> es un directorio con la estructura:
#   proposal.md    — metadata del proposal (frontmatter + body)
#   tasks.md      — lista de tasks en formato - [ ] Título
#   design.md     — (opcional) markdown de diseño
#   specs/*.md    — (opcional) specs técnicas
#
# Comportamiento:
#   - Si el proposal slug ya existe y no hay --force → SKIP (idempotente)
#   - Con --force → re-ingiere (sobrescribe proposal/plan/tasks/specs existentes)
#   - tasks.md sigue las mismas reglas de parsing que teamdb-plan.sh
#   - specs/*.md se ingestan en la tabla specs
#   - design.md se escribe en plans.design_md (solo si existe el plan)
#   - Atomicidad: BEGIN IMMEDIATE + rollback en caso de error
#
# No inventa fechas. Si tasks.md tiene un token de fecha explícito, lo usa;
# si no, due_date queda NULL.
#
# Seguridad: usa teamdb_exec_write con parameter binding (R10).
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LIB_PATH="$SCRIPT_DIR/lib-teamdb.sh"
# shellcheck disable=SC1091
[ -f "$LIB_PATH" ] || LIB_PATH="$SCRIPT_DIR/lib/lib-teamdb.sh"
# shellcheck disable=SC1090
if [ -f "$LIB_PATH" ]; then
  # shellcheck disable=SC1090
  . "$LIB_PATH"
else
  echo "ERROR: lib-teamdb.sh no encontrado" >&2
  exit 1
fi

usage() {
  cat <<EOF
Uso: teamdb-ingest-change.sh <project> <change-dir> [--dry-run] [--force]

Ingiere un change dir en la DB. Estructura esperada del change-dir:
  proposal.md   — frontmatter (title, status, agent) + intent body
  tasks.md     — formato - [ ] Título (mismo parser que teamdb-plan.sh)
  design.md    — (opcional) arquitectura
  specs/*.md   — (opcional) specs técnicas

Flags:
  --dry-run    solo muestra qué haría sin tocar la DB
  --force      re-ingiere aunque el slug ya exista

Idempotente sin --force: si el proposal ya existe, lo.skip.
EOF
  exit 2
}

DRY_RUN=false
FORCE=false
PROJECT=""
CHANGE_DIR=""
if [ "$#" -ge 1 ]; then
  for arg in "$@"; do
    case "$arg" in
      --dry-run) DRY_RUN=true ;;
      --force) FORCE=true ;;
      -h|--help) usage ;;
    esac
  done
  while [ "$#" -gt 0 ]; do
    case "$1" in
      --dry-run|--force) shift ;;
      -h|--help) usage ;;
      -*) echo "[ERROR] opción desconocida: $1" >&2; exit 2 ;;
      *) PROJECT="$1"; CHANGE_DIR="$2"; break ;;
    esac
    shift
  done
fi

[ $# -lt 2 ] && usage

PROJECT="${1:?Falta project}"
CHANGE_DIR="${2:?Falta change-dir}"

[ -d "$CHANGE_DIR" ] || { echo "[ERROR] change-dir no existe: $CHANGE_DIR" >&2; exit 1; }

LOCK_DIR="$PROJECT/.opencode/context/.locks/team"
mkdir -p "$(dirname "$LOCK_DIR")" 2>/dev/null || true
if ! teamdb_lock "$LOCK_DIR" 10; then
  exit 1
fi
trap 'teamdb_unlock "$LOCK_DIR"' EXIT

DB="$(teamdb_project_path "$PROJECT")"
[ -f "$DB" ] || { echo "[ERROR] DB no existe: $DB" >&2; exit 1; }

PROPOSAL_MD="$CHANGE_DIR/proposal.md"
[ -f "$PROPOSAL_MD" ] || { echo "[ERROR] proposal.md no encontrado: $PROPOSAL_MD" >&2; exit 1; }

NOW="$(date -u +%Y-%m-%dT%H:%M:%SZ)"

# ─────────────────────────────────────────────────────────────────────────────
# 1. Parsear proposal.md (frontmatter + body)
# ─────────────────────────────────────────────────────────────────────────────
parse_proposal() {
  python3 - "$PROPOSAL_MD" <<'PYEOF'
import re, sys, os

p = sys.argv[1]
with open(p, encoding='utf-8') as f:
    content = f.read()

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
        if m: status = m.group(1).strip().lower()
        m = re.match(r'^agent:\s*(.+?)\s*$', line)
        if m: agent = m.group(1).strip()

if not title:
    m = re.search(r'^#\s+(.+?)\s*$', content, re.MULTILINE)
    if m: title = m.group(1).strip()

base = os.path.basename(os.path.dirname(p))
if title:
    slug = re.sub(r'[^a-z0-9]+', '-', title.lower()).strip('-')
else:
    slug = re.sub(r'^\d{4}-\d{2}-\d{2}-', '', base)
    slug = re.sub(r'[^a-z0-9]+', '-', slug.lower()).strip('-')

intent = content
if fm_match:
    after_fm = content[fm_match.end():]
    intent = after_fm.strip().replace('\n', '\\n')

valid_statuses = ('draft', 'approved', 'rejected')
if status not in valid_statuses:
    status = 'draft'

print('\t'.join([slug, title or slug, status, agent, intent]))
PYEOF
}

parsed="$(parse_proposal)"
IFS=$'\t' read -r PROPOSAL_SLUG PROPOSAL_TITLE PROPOSAL_STATUS PROPOSAL_AGENT PROPOSAL_INTENT <<EOF
$parsed
EOF
PROPOSAL_INTENT="${PROPOSAL_INTENT//\\n/$'\n'}"

[ -n "$PROPOSAL_SLUG" ] || { echo "[ERROR] no pude derivar slug de proposal" >&2; exit 1; }

# ─────────────────────────────────────────────────────────────────────────────
# 2. Verificar si ya existe (idempotencia)
# ─────────────────────────────────────────────────────────────────────────────
EXISTING_PROPOSAL_ID="$(teamdb_exec_value "$DB" "SELECT id FROM proposals WHERE slug = ?" "$PROPOSAL_SLUG" 2>/dev/null || echo "")"
if [ -n "$EXISTING_PROPOSAL_ID" ] && [ "$FORCE" != "true" ]; then
  echo "SKIP: proposal '$PROPOSAL_SLUG' ya existe (usar --force para re-ingerir)"
  exit 0
fi

# ─────────────────────────────────────────────────────────────────────────────
# 3. Parsear tasks.md (mismo parser que teamdb-plan.sh L106-143)
# ─────────────────────────────────────────────────────────────────────────────
TASKS_MD="$CHANGE_DIR/tasks.md"
TMP_DIR="$(mktemp -d)"
TASKS_TSV="$TMP_DIR/tasks.tsv"
: > "$TASKS_TSV"

if [ -f "$TASKS_MD" ]; then
  ORDER=0
  while IFS= read -r line; do
    case "$line" in
      "- [ ] "*|"- [x] "*|"-[] "*)
        if [[ "$line" == "- [ ] "* ]]; then
          raw="${line#"- [ ] "}"
        elif [[ "$line" == "- [x] "* ]]; then
          raw="${line#"- [x] "}"
        else
          raw="${line#"-[] "}"
        fi
        deps=""
        title="$raw"
        case "$raw" in
          *" _depends: ["*"]"*)
            deps_part="${raw##*_depends: \[}"
            deps_part="${deps_part%\]}"
            title="${raw% _depends: \[*\]}"
            deps="$(printf '%s' "$deps_part" | tr ',' '\n' | sed 's/^[[:space:]]*//;s/[[:space:]]*$//' | tr '\n' ',' | sed 's/,$//')"
            ;;
        esac
        slug_part="$(printf '%s' "$title" | tr '[:upper:]' '[:lower:]' | tr -cs 'a-z0-9' '-' | sed 's/^-//;s/-$//;s/--*/-/g')"
        [ -z "$slug_part" ] && slug_part="$ORDER"
        task_slug="task-$slug_part"
        printf '%s\t%s\t%s\t%s\n' "$ORDER" "$task_slug" "$title" "$deps" >> "$TASKS_TSV"
        ORDER=$((ORDER + 1))
        ;;
    esac
  done < "$TASKS_MD"
fi

# ─────────────────────────────────────────────────────────────────────────────
# 4. Parsear specs/*.md
# ─────────────────────────────────────────────────────────────────────────────
SPECS_DIR="$CHANGE_DIR/specs"
SPECS_TSV="$TMP_DIR/specs.tsv"
: > "$SPECS_TSV"

if [ -d "$SPECS_DIR" ]; then
  ORDER=0
  for spec_file in "$SPECS_DIR"/*.md; do
    [ -f "$spec_file" ] || continue
    base="$(basename "$spec_file" .md)"
    if [ "${base#spec-}" = "$base" ]; then
      spec_slug="spec-$base"
    else
      spec_slug="$base"
    fi
    content="$(cat "$spec_file")"
    first_heading="$(printf '%s' "$content" | sed -n 's/^# \([^ ]*\)/\1/p' | head -1)"
    [ -z "$first_heading" ] && first_heading="$base"
    content_escaped="${content//$'\\n'/\\n}"
    printf '%s\t%s\t%s\t%s\n' "$ORDER" "$spec_slug" "$first_heading" "$content_escaped" >> "$SPECS_TSV"
    ORDER=$((ORDER + 1))
  done
fi

# ─────────────────────────────────────────────────────────────────────────────
# 5. Leer design.md si existe
# ─────────────────────────────────────────────────────────────────────────────
DESIGN_MD="$CHANGE_DIR/design.md"
DESIGN_CONTENT=""
if [ -f "$DESIGN_MD" ]; then
  DESIGN_CONTENT="$(cat "$DESIGN_MD")"
fi

# ─────────────────────────────────────────────────────────────────────────────
# 6. Escritura atómica a la DB
# ─────────────────────────────────────────────────────────────────────────────
if [ "$DRY_RUN" = true ]; then
  echo "[dry-run] proposal: slug=$PROPOSAL_SLUG title=$PROPOSAL_TITLE status=$PROPOSAL_STATUS agent=$PROPOSAL_AGENT"
  echo "[dry-run] tasks: $(wc -l < "$TASKS_TSV") líneas parseadas"
  echo "[dry-run] specs: $(wc -l < "$SPECS_TSV") archivos"
  if [ -n "$DESIGN_CONTENT" ]; then
    echo "[dry-run] design: ${#DESIGN_CONTENT} bytes"
  fi
  rm -rf "$TMP_DIR"
  exit 0
fi

python3 - "$DB" "$PROPOSAL_SLUG" "$PROPOSAL_TITLE" "$PROPOSAL_STATUS" "$PROPOSAL_AGENT" "$PROPOSAL_INTENT" "$NOW" "$DESIGN_CONTENT" "$TASKS_TSV" "$SPECS_TSV" <<'PYEOF'
import sqlite3, sys, os

db, slug, title, status, agent, intent, now, design_content, tasks_tsv, specs_tsv = sys.argv[1:11]

conn = sqlite3.connect(db, timeout=5)
conn.execute("PRAGMA foreign_keys=ON")
try:
    conn.execute("BEGIN IMMEDIATE")

    conn.execute(
        "INSERT INTO proposals(slug,title,intent_md,status,agent,created_at,updated_at) VALUES(?,?,?,?,?,?,?) "
        "ON CONFLICT(slug) DO UPDATE SET title=excluded.title,intent_md=excluded.intent_md,status=excluded.status,agent=excluded.agent,updated_at=excluded.updated_at",
        (slug, title, intent, status, agent, now, now))
    proposal_id = conn.execute("SELECT id FROM proposals WHERE slug = ?", (slug,)).fetchone()[0]

    conn.execute(
        "INSERT INTO plans(slug,title,proposal_id,design_md,status,agent,created_by,updated_by,version,created_at,updated_at) "
        "VALUES(?,?,?,?,?,'sol',?,?,1,?,?) "
        "ON CONFLICT(slug) DO UPDATE SET title=excluded.title,proposal_id=excluded.proposal_id,design_md=excluded.design_md,updated_at=excluded.updated_at,updated_by=excluded.updated_by",
        (slug, title, proposal_id, design_content, 'draft', agent, agent, now, now))
    plan_id = conn.execute("SELECT id FROM plans WHERE slug = ?", (slug,)).fetchone()[0]

    task_count = 0
    if os.path.exists(tasks_tsv):
        with open(tasks_tsv) as f:
            for line in f:
                line = line.rstrip('\n')
                if not line:
                    continue
                idx, tslug, ttitle, deps = line.split('\t', 3)
                conn.execute(
                    "INSERT OR IGNORE INTO tasks(plan_id,slug,title,status,priority,order_index,owner,created_at,updated_at) "
                    "VALUES(?,?,?,'pending',2,?,?,?,?)",
                    (plan_id, tslug, ttitle, idx, agent, now, now))
                task_count += 1
                if deps:
                    for dep_slug in deps.split(','):
                        if not dep_slug:
                            continue
                        conn.execute(
                            "INSERT OR IGNORE INTO task_dependencies(task_id, depends_on_task_id, type, created_at) "
                            "SELECT t.id, d.id, 'blocks', ? FROM tasks t JOIN tasks d ON d.plan_id = t.plan_id AND d.slug = ? "
                            "WHERE t.plan_id = ? AND t.slug = ?",
                            (now, dep_slug, plan_id, tslug))

    spec_count = 0
    if os.path.exists(specs_tsv):
        with open(specs_tsv) as f:
            for line in f:
                line = line.rstrip('\n')
                if not line:
                    continue
                parts = line.split('\t', 3)
                if len(parts) < 4:
                    continue
                sorder, sslug, stitle, sbody = parts
                sbody = sbody.replace('\\n', '\n')
                conn.execute(
                    "INSERT INTO specs(plan_id,slug,title,body_md,order_index,created_at,updated_at) VALUES(?,?,?,?,?,?,?) "
                    "ON CONFLICT(plan_id,slug) DO UPDATE SET title=excluded.title,body_md=excluded.body_md,order_index=excluded.order_index,updated_at=excluded.updated_at",
                    (plan_id, sslug, stitle, sbody, sorder, now, now))
                spec_count += 1

    conn.commit()
    print("ingested: %s (proposal_id=%d, plan_id=%d, %d tasks, %d specs)" % (slug, proposal_id, plan_id, task_count, spec_count))
except Exception as e:
    conn.rollback()
    print("[ERROR] %s" % e, file=sys.stderr)
    sys.exit(1)
PYEOF

INGEST_RC=$?

if [ "$INGEST_RC" = "0" ]; then
  teamdb_refresh_dump "$PROJECT" >/dev/null 2>&1 || true
fi

rm -rf "$TMP_DIR"
exit $INGEST_RC
