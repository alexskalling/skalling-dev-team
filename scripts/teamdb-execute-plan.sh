#!/usr/bin/env bash
# teamdb-execute-plan.sh — Descubre la siguiente task runnable y la ofrece al caller.
# T-2.17v2 / DC-3: solo orquesta. NO ejecuta shell arbitrario desde la DB.
# Compatible: delega a teamdb-claim.sh; el caller (Teo) hace el trabajo de ingeniería.
# Lock file (se aplica al final, después de parsing $PROJECT)
set -euo pipefail

PROJECT="${PROJECT:-$(pwd)}"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# Lock file para evitar race conditions entre agentes
LOCK_DIR="$PROJECT/.opencode/context"
LOCK_FILE="$LOCK_DIR/team.lock"
mkdir -p "$LOCK_DIR" 2>/dev/null || true
if command -v flock >/dev/null 2>&1; then
  exec 9>"$LOCK_FILE" 2>/dev/null || true
  flock -w 10 9 || { echo "ERROR: no se pudo obtener lock en $LOCK_FILE" >&2; exit 1; }
fi
trap 'exec 9>&- 2>/dev/null' EXIT

# shellcheck disable=SC1091
if [ -f "$SCRIPT_DIR/lib-teamdb.sh" ]; then
  . "$SCRIPT_DIR/lib-teamdb.sh"
elif [ -f "$SCRIPT_DIR/lib/lib-teamdb.sh" ]; then
  . "$SCRIPT_DIR/lib/lib-teamdb.sh"
else
  echo "ERROR: lib-teamdb.sh no encontrado" >&2
  exit 1
fi

usage() {
  cat <<EOF
Uso: teamdb-execute-plan.sh <plan> [project]

Descubre la siguiente task runnable del plan y emite un JSON con:
  { "plan_slug": ..., "next_task": { "slug": ..., "title": ... }, "claim_command": "..." }

NO ejecuta shell desde la DB. Devuelve el comando que el caller (Teo) debe
ejecutar (tipicamente: bash teamdb-claim.sh <plan> <task> --actor=teo ...).
EOF
  exit 2
}

[ "${1:-}" = "--help" ] || [ "${1:-}" = "-h" ] && usage
[ $# -ge 1 ] || usage

PLAN_SLUG="$1"
PROJECT="${2:-$(pwd)}"
[ -d "$PROJECT" ] || PROJECT="$(pwd)"

DB="$(teamdb_project_path "$PROJECT")"
[ -f "$DB" ] || { echo "[ERROR] DB no existe: $DB" >&2; exit 1; }

# Validar que el plan existe
PLAN_ID="$(teamdb_exec_value "$DB" "SELECT id FROM plans WHERE slug = ?" "$PLAN_SLUG")"
[ -n "$PLAN_ID" ] || { echo "[ERROR] plan no encontrado: $PLAN_SLUG" >&2; exit 1; }

# Descubrir la siguiente task runnable
NEXT_JSON="$(teamdb_exec_query "$DB" "
  SELECT t.slug, t.title, t.priority, t.order_index
  FROM tasks t
  WHERE t.plan_id = ? AND t.status = 'pending'
    AND NOT EXISTS (
      SELECT 1 FROM task_dependencies d
      JOIN tasks dep ON dep.id = d.depends_on_task_id
      WHERE d.task_id = t.id AND dep.status NOT IN ('approved', 'resolved')
    )
  ORDER BY t.priority DESC, t.order_index
  LIMIT 1
" "$PLAN_ID")"

if [ "$NEXT_JSON" = "[]" ] || [ -z "$NEXT_JSON" ]; then
  echo "{\"plan_slug\":\"$PLAN_SLUG\",\"next_task\":null,\"message\":\"no runnable tasks\"}"
  exit 0
fi

# Emitir JSON con info de la siguiente task + claim command
echo "$NEXT_JSON" | python3 -c "
import json, sys
try:
    rows = json.loads(sys.stdin.read())
    if not rows:
        print('{\"plan_slug\":\"$PLAN_SLUG\",\"next_task\":null}')
        sys.exit(0)
    r = rows[0]
    claim_cmd = f'teamdb-claim.sh $PLAN_SLUG {r[\"slug\"]} --actor=\$TEAMDB_ACTOR --input-hash=<hash> --ttl=300 $PROJECT'
    out = {
        'plan_slug': '$PLAN_SLUG',
        'next_task': {'slug': r['slug'], 'title': r['title'], 'priority': r['priority'], 'order_index': r['order_index']},
        'claim_command': claim_cmd,
    }
    print(json.dumps(out, indent=2))
except Exception as e:
    print(f'{{\"error\": \"{e}\"}}', file=sys.stderr)
    sys.exit(1)
"
