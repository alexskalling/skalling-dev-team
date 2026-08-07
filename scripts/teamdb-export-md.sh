#!/usr/bin/env bash
# teamdb-export-md.sh — Genera archivos .md desde TeamDB (DB es fuente, MD es output)
# T-2.15: NO bidireccional. MD siempre lleva header GENERATED.
# Lock file (se aplica al final, después de parsing $PROJECT)
set -euo pipefail

PROJECT="${PROJECT:-$(pwd)}"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# Lock file para evitar race conditions entre agentes
# shellcheck disable=SC1091
if [ -f "$SCRIPT_DIR/lib-teamdb.sh" ]; then
  . "$SCRIPT_DIR/lib-teamdb.sh"
elif [ -f "$SCRIPT_DIR/lib/lib-teamdb.sh" ]; then
  . "$SCRIPT_DIR/lib/lib-teamdb.sh"
else
  echo "ERROR: lib-teamdb.sh no encontrado" >&2
  exit 1
fi

# Política: NO bidireccional — --from-md rechazado
[ "${1:-}" = "--from-md" ] && { echo "[ERROR] --from-md no soportado. Markdown es OUTPUT, no INPUT." >&2; exit 2; }
[ "${1:-}" = "--help" ] || [ "${1:-}" = "-h" ] && {
  cat <<EOF
Uso: teamdb-export-md.sh <project> [--plan=slug]

Genera archivos .md en .opencode/changes/<plan-slug>/ desde la DB.
Output SIEMPRE lleva header '<!-- GENERATED -->'. NO acepta --from-md.
EOF
  exit 0
}

PROJECT=""
PLAN_FILTER=""
while [ "$#" -gt 0 ]; do
  case "$1" in
    --plan=*) PLAN_FILTER="${1#--plan=}" ;;
    --help|-h) shift; continue ;;
    -*) echo "[ERROR] argumento desconocido: $1" >&2; exit 2 ;;
    *)
      if [ -z "$PROJECT" ]; then
        PROJECT="$1"
      else
        echo "[ERROR] argumento desconocido: $1" >&2; exit 2
      fi
      ;;
  esac
  shift || break
done

[ -n "$PROJECT" ] || { echo "Uso: teamdb-export-md.sh <project> [--plan=slug]" >&2; exit 2; }

# Lock cross-platform (mkdir-based, sin flock). v0.8.3
LOCK_DIR="$PROJECT/.opencode/context/.locks/team"
mkdir -p "$(dirname "$LOCK_DIR")" 2>/dev/null || true
if ! teamdb_lock "$LOCK_DIR" 10; then
  exit 1
fi
trap 'teamdb_unlock "$LOCK_DIR"' EXIT

DB="$(teamdb_project_path "$PROJECT")"
[ -f "$DB" ] || { echo "[ERROR] DB no existe: $DB" >&2; exit 1; }
CHANGES_DIR="$PROJECT/.opencode/changes"
mkdir -p "$CHANGES_DIR"

NOW="$(date -u +%Y-%m-%dT%H:%M:%SZ)"

# Listar plans a exportar
if [ -n "$PLAN_FILTER" ]; then
  PLAN_ID="$(teamdb_exec_value "$DB" "SELECT id FROM plans WHERE slug = ?" "$PLAN_FILTER")"
  [ -n "$PLAN_ID" ] || { echo "[ERROR] plan no encontrado: $PLAN_FILTER" >&2; exit 1; }
  PLAN_IDS="$PLAN_ID"
else
  PLAN_IDS="$(teamdb_exec_query "$DB" "SELECT id FROM plans" | python3 -c "
import json, sys
try:
    rows = json.loads(sys.stdin.read())
    print('\n'.join(str(r['id']) for r in rows))
except Exception:
    pass
")"
fi

if [ -z "$PLAN_IDS" ]; then
  echo "exported: $CHANGES_DIR (no plans)"
  exit 0
fi

GENERATED_COUNT=0

for PLAN_ID in $PLAN_IDS; do
  SLUG="$(teamdb_exec_value "$DB" "SELECT slug FROM plans WHERE id = ?" "$PLAN_ID")"
  [ -n "$SLUG" ] || continue

  PLAN_DIR="$CHANGES_DIR/$SLUG"
  mkdir -p "$PLAN_DIR/specs"

  HEADER="<!-- GENERATED from teamdb on $NOW. DO NOT EDIT. Source of truth: $DB.
     Bidirectional is PROHIBITED. To update DB: edit via teamdb-plan.sh / teamdb-amend.sh.
     To regenerate: bash scripts/teamdb-export-md.sh $PROJECT -->"

  # proposal.md
  {
    echo "$HEADER"
    echo ""
    echo "# Proposal: $SLUG"
    echo ""
    PROPOSAL_INFO="$(teamdb_exec_query "$DB" "SELECT title, COALESCE(intent_md, ''), status FROM proposals WHERE slug = ?" "$SLUG")"
    PTITLE=$(echo "$PROPOSAL_INFO" | python3 -c "import json,sys; r=json.loads(sys.stdin.read()); print(r[0]['title'] if r else '')" 2>/dev/null || echo "")
    PINTENT=$(echo "$PROPOSAL_INFO" | python3 -c "import json,sys; r=json.loads(sys.stdin.read()); print(r[0]['intent_md'] if r else '')" 2>/dev/null || echo "")
    PSTATUS=$(echo "$PROPOSAL_INFO" | python3 -c "import json,sys; r=json.loads(sys.stdin.read()); print(r[0]['status'] if r else '')" 2>/dev/null || echo "")
    [ -z "$PTITLE" ] && PTITLE="$SLUG"
    [ -z "$PSTATUS" ] && PSTATUS="draft"
    echo "- **Slug:** $SLUG"
    echo "- **Title:** $PTITLE"
    echo "- **Status:** $PSTATUS"
    echo ""
    echo "## Intent"
    echo ""
    echo "$PINTENT"
    echo ""
    echo "<!-- Footer: regenerar desde DB con teamdb-export-md.sh -->"
  } > "$PLAN_DIR/proposal.md"

  # design.md
  {
    echo "$HEADER"
    echo ""
    echo "# Design: $SLUG"
    echo ""
    DESIGN_MD="$(teamdb_exec_value "$DB" "SELECT design_md FROM plans WHERE id = ?" "$PLAN_ID")"
    echo "$DESIGN_MD"
    echo ""
    echo "## ADRs (design_notes)"
    echo ""
    teamdb_exec_query "$DB" "SELECT title, COALESCE(context_md, ''), COALESCE(decision_md, ''), status FROM design_notes WHERE plan_id = ? ORDER BY decided_at DESC" "$PLAN_ID" | python3 -c "
import json, sys
try:
    rows = json.loads(sys.stdin.read())
    for r in rows:
        print('###', r['title'])
        print('**Context:**', r['context_md'])
        print()
        print('**Decision:**', r['decision_md'])
        print('**Status:**', r['status'])
        print()
except Exception:
    pass
"
    echo "<!-- Footer: regenerar desde DB -->"
  } > "$PLAN_DIR/design.md"

  # tasks.md
  {
    echo "$HEADER"
    echo ""
    echo "# Tasks for $SLUG"
    echo ""
    teamdb_exec_query "$DB" "SELECT slug, title, status, priority, COALESCE(owner, '') AS owner FROM tasks WHERE plan_id = ? ORDER BY order_index" "$PLAN_ID" | python3 -c "
import json, sys
try:
    rows = json.loads(sys.stdin.read())
    print('| Status | Slug | Priority | Owner | Title |')
    print('|--------|------|----------|-------|-------|')
    for r in rows:
        print('|', r['status'], '|', r['slug'], '|', r['priority'], '|', r['owner'], '|', r['title'], '|')
except Exception as e:
    print('<!-- error:', e, '-->', file=sys.stderr)
"
    echo ""
    echo "<!-- Footer -->"
  } > "$PLAN_DIR/tasks.md"

  GENERATED_COUNT=$((GENERATED_COUNT + 1))
done

echo "exported: $CHANGES_DIR ($GENERATED_COUNT plans)"
