#!/usr/bin/env bash
# teamdb-claim.sh — Atomic claim con lease (epoch), input_hash determinista,
# validacion de status terminal + deps blocks, release con whitelist de transiciones.
# Issues 1, 2, 3, 4, 5, 7
# Lock file para evitar race conditions entre agentes
LOCK_DIR="${PROJECT:-$(pwd)}/.opencode/context"
LOCK_FILE="$LOCK_DIR/team.lock"
mkdir -p "$LOCK_DIR" 2>/dev/null || true
exec 9>"$LOCK_FILE" 2>/dev/null || true
if command -v flock >/dev/null 2>&1; then
  flock -w 10 9 || { echo "ERROR: no se pudo obtener lock en $LOCK_FILE" >&2; exit 1; }
fi
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck disable=SC1091
if [ -f "$SCRIPT_DIR/lib-teamdb.sh" ]; then
  . "$SCRIPT_DIR/lib-teamdb.sh"
elif [ -f "$SCRIPT_DIR/lib/lib-teamdb.sh" ]; then
  . "$SCRIPT_DIR/lib/lib-teamdb.sh"
else
  echo "ERROR: lib-teamdb.sh no encontrado" >&2
  exit 1
fi

# Estados terminales: claim NO permitido. Whitelist (validada en Python).
# shellcheck disable=SC2034
TERMINAL_TASK_STATUSES="approved resolved rejected blocked"

usage() {
  cat <<EOF
Uso:
  teamdb-claim.sh <plan> <task> [--actor=X] [--input-hash=H] [--ttl=N] [project]
  teamdb-claim.sh --resume [--actor=X] [project]
  teamdb-claim.sh --release <claim-id> [--status=done|failed] [--by=actor] [project]
  teamdb-claim.sh --advance <plan> <task> --to=approved|resolved [--by=actor] [project]

Estados terminales (claim rechazado): approved, resolved, rejected, blocked.
Input hash por defecto: hash determinista de (plan, task, actor, plan_version).
Lease: epoch entero (segundos Unix). 1 claim activo por task.
Release: el actor del claim es el unico que puede liberar. done → in_review (no resolved).
Advance (transiciones verificadas): in_review→approved solo por jhon; approved→resolved solo por pau.
EOF
  exit 2
}

[ "${1:-}" = "--help" ] || [ "${1:-}" = "-h" ] && usage

PROJECT_DEFAULT="$(pwd)"

# --resume
if [ "${1:-}" = "--resume" ]; then
  ACTOR="${TEAMDB_ACTOR:-unknown}"
  PROJECT="$PROJECT_DEFAULT"
  shift
  while [ "$#" -gt 0 ]; do
    case "$1" in
      --actor=*) ACTOR="${1#--actor=}" ;;
      --actor) shift; ACTOR="${1:-unknown}" ;;
      *) PROJECT="$1" ;;
    esac
    shift || break
  done
  [ -d "$PROJECT" ] || PROJECT="$PROJECT_DEFAULT"
  DB="$(teamdb_project_path "$PROJECT")"
  [ -f "$DB" ] || { echo "[ERROR] no DB" >&2; exit 1; }
  # Resume: claims activos del actor con lease vigente (epoch comparison)
  python3 - "$DB" "$ACTOR" <<'PYEOF'
import sqlite3, sys, json
db, actor = sys.argv[1], sys.argv[2]
conn = sqlite3.connect(db)
conn.row_factory = sqlite3.Row
now = int(__import__('time').time())
rows = conn.execute("""
    SELECT c.id, c.task_id, c.attempt, c.input_hash, c.lease_until,
           t.slug AS task_slug, t.plan_id, p.slug AS plan_slug
    FROM task_claims c
    JOIN tasks t ON t.id = c.task_id
    JOIN plans p ON p.id = t.plan_id
    WHERE c.actor = ? AND c.status = 'active' AND CAST(c.lease_until AS INTEGER) > ?
    ORDER BY c.claimed_at
""", (actor, now)).fetchall()
result = [{
    'claim_id': r['id'],
    'task_id': r['task_id'],
    'task_slug': r['task_slug'],
    'plan_id': r['plan_id'],
    'plan_slug': r['plan_slug'],
    'attempt': r['attempt'],
    'input_hash': r['input_hash'],
    'lease_until': r['lease_until'],
} for r in rows]
print(json.dumps(result, indent=2))
PYEOF
  exit 0
fi

# --release
if [ "${1:-}" = "--release" ]; then
  CLAIM_ID="${2:?--release requiere <claim-id>}"
  shift 2 || true
  NEW_STATUS="done"
  RELEASE_BY="${TEAMDB_ACTOR:-unknown}"
  PROJECT="$PROJECT_DEFAULT"
  while [ "$#" -gt 0 ]; do
    case "$1" in
      --status=*) NEW_STATUS="${1#--status=}" ;;
      --status) shift; NEW_STATUS="${1:-done}" ;;
      --by=*) RELEASE_BY="${1#--by=}" ;;
      --by) shift; RELEASE_BY="${1:-}" ;;
      *) PROJECT="$1" ;;
    esac
    shift || break
  done
  [ -d "$PROJECT" ] || PROJECT="$PROJECT_DEFAULT"
  DB="$(teamdb_project_path "$PROJECT")"
  [ -f "$DB" ] || { echo "[ERROR] no DB" >&2; exit 1; }
  python3 - "$DB" "$CLAIM_ID" "$NEW_STATUS" "$RELEASE_BY" <<'PYEOF'
import sqlite3, sys, json
db, claim_id, new_status, release_by = sys.argv[1], int(sys.argv[2]), sys.argv[3], sys.argv[4]
if new_status not in ('done', 'failed'):
    json.dump({'error': 'invalid status: %s (usa done|failed)' % new_status}, sys.stdout)
    sys.exit(1)
conn = sqlite3.connect(db, timeout=5)
conn.execute("PRAGMA foreign_keys=ON")
conn.row_factory = sqlite3.Row
try:
    conn.execute("BEGIN IMMEDIATE")
    c = conn.execute("SELECT id, actor, status, task_id FROM task_claims WHERE id = ?", (claim_id,)).fetchone()
    if not c:
        json.dump({'error': 'claim not found: %d' % claim_id}, sys.stdout)
        conn.rollback(); sys.exit(1)
    if c['status'] != 'active':
        json.dump({'error': 'claim not active (status=%s)' % c['status']}, sys.stdout)
        conn.rollback(); sys.exit(1)
    if c['actor'] != release_by:
        json.dump({'error': 'wrong actor (owner=%s, by=%s)' % (c['actor'], release_by)}, sys.stdout)
        conn.rollback(); sys.exit(1)
    now = int(__import__('time').time())
    conn.execute("UPDATE task_claims SET status = ?, released_at = ? WHERE id = ?",
                 (new_status, now, claim_id))
    if new_status == 'done':
        # Whitelist: in_progress|pending → in_review (no resolved)
        conn.execute("""
            UPDATE tasks SET status = 'in_review', updated_at = ?
            WHERE id = ? AND status IN ('pending', 'in_progress')
        """, (now, c['task_id']))
    elif new_status == 'failed':
        conn.execute("""
            UPDATE tasks SET status = 'pending', updated_at = ?
            WHERE id = ?
        """, (now, c['task_id']))
    conn.execute("INSERT INTO audit_log(ts, agent, action, table_name, actor_source) VALUES(datetime('now'), ?, 'release', 'task_claims', 'helper')",
                 (release_by,))
    conn.commit()
    print('released: claim-id=%d status=%s' % (claim_id, new_status))
except Exception as e:
    conn.rollback()
    json.dump({'error': str(e)}, sys.stdout)
    sys.exit(1)
PYEOF
  exit 0
fi

# --advance: transiciones verificadas in_review→approved (Jhon) y approved→resolved (Pau)
if [ "${1:-}" = "--advance" ]; then
  PLAN_SLUG="${2:?--advance requiere <plan>}"
  TASK_SLUG="${3:?--advance requiere <task>}"
  shift 3 || true
  TARGET_STATUS=""
  ADVANCE_BY="${TEAMDB_ACTOR:-unknown}"
  PROJECT="$PROJECT_DEFAULT"
  while [ "$#" -gt 0 ]; do
    case "$1" in
      --to=*) TARGET_STATUS="${1#--to=}" ;;
      --to) shift; TARGET_STATUS="${1:-}" ;;
      --by=*) ADVANCE_BY="${1#--by=}" ;;
      --by) shift; ADVANCE_BY="${1:-}" ;;
      *) PROJECT="$1" ;;
    esac
    shift || break
  done
  if [ -z "$TARGET_STATUS" ]; then
    echo "ERROR: --advance requiere --to=approved|resolved" >&2; exit 2
  fi
  if [ "$TARGET_STATUS" != "approved" ] && [ "$TARGET_STATUS" != "resolved" ]; then
    echo "ERROR: --to debe ser approved|resolved (recibido: $TARGET_STATUS)" >&2; exit 2
  fi
  [ -d "$PROJECT" ] || PROJECT="$PROJECT_DEFAULT"
  DB="$(teamdb_project_path "$PROJECT")"
  [ -f "$DB" ] || { echo "[ERROR] no DB" >&2; exit 1; }
  python3 - "$DB" "$PLAN_SLUG" "$TASK_SLUG" "$TARGET_STATUS" "$ADVANCE_BY" <<'PYEOF'
import sqlite3, sys, json, time
db, plan_slug, task_slug, target, actor = sys.argv[1:6]
if target == 'approved' and actor != 'jhon':
    json.dump({'error': 'in_review->approved requiere actor=jhon (verificador)'}, sys.stdout)
    sys.exit(2)
if target == 'resolved' and actor != 'pau':
    json.dump({'error': 'approved->resolved requiere actor=pau (documentalist)'}, sys.stdout)
    sys.exit(2)
now = int(time.time())
conn = sqlite3.connect(db, timeout=5)
conn.execute("PRAGMA foreign_keys=ON")
conn.row_factory = sqlite3.Row
try:
    conn.execute("BEGIN IMMEDIATE")
    t = conn.execute("""
        SELECT id, status FROM tasks
        WHERE plan_id=(SELECT id FROM plans WHERE slug=?) AND slug=?
    """, (plan_slug, task_slug)).fetchone()
    if not t:
        json.dump({'error': 'task not found: %s/%s' % (plan_slug, task_slug)}, sys.stdout)
        conn.rollback(); sys.exit(1)
    if target == 'approved' and t['status'] != 'in_review':
        json.dump({'error': 'approved requiere status=in_review (actual=%s)' % t['status']}, sys.stdout)
        conn.rollback(); sys.exit(1)
    if target == 'resolved' and t['status'] != 'approved':
        json.dump({'error': 'resolved requiere status=approved (actual=%s)' % t['status']}, sys.stdout)
        conn.rollback(); sys.exit(1)
    conn.execute("UPDATE tasks SET status = ?, updated_at = ? WHERE id = ?", (target, now, t['id']))
    conn.execute("INSERT INTO audit_log(ts, agent, action, table_name, actor_source) VALUES(datetime('now'), ?, 'advance', 'tasks', 'helper')", (actor,))
    conn.commit()
    print('advanced: task=%s status=%s by=%s' % (task_slug, target, actor))
except Exception as e:
    conn.rollback()
    json.dump({'error': str(e)}, sys.stdout)
    sys.exit(1)
PYEOF
  exit 0
fi

# Subcomando principal: claim
PLAN_SLUG="${1:?Falta plan slug}"
TASK_SLUG="${2:?Falta task slug}"
shift 2
ACTOR=""
INPUT_HASH=""
TTL=300
PROJECT="$PROJECT_DEFAULT"
while [ "$#" -gt 0 ]; do
  case "$1" in
    --actor=*) ACTOR="${1#--actor=}" ;;
    --actor) shift; ACTOR="${1:-}" ;;
    --input-hash=*) INPUT_HASH="${1#--input-hash=}" ;;
    --ttl=*) TTL="${1#--ttl=}" ;;
    *) PROJECT="$1" ;;
  esac
  shift || break
done

ACTOR="${ACTOR:-${TEAMDB_ACTOR:-unknown}}"
[ -d "$PROJECT" ] || PROJECT="$PROJECT_DEFAULT"
DB="$(teamdb_project_path "$PROJECT")"
[ -f "$DB" ] || { echo "[ERROR] DB no existe: $DB" >&2; exit 1; }

# Input hash determinista (Issue 3): plan_slug + task_slug + actor + plan_version
# Si el caller no provee --input-hash, calculamos un hash determinista.
# Lo calculamos dentro de Python (en la transaccion) para tener plan_version.
INPUT_HASH="${INPUT_HASH:-__AUTO__}"

PLAN_ID="$(teamdb_exec_value "$DB" "SELECT id FROM plans WHERE slug = ?" "$PLAN_SLUG")"
[ -n "$PLAN_ID" ] || { echo "[ERROR] plan no encontrado: $PLAN_SLUG" >&2; exit 1; }

python3 - "$DB" "$PLAN_ID" "$PLAN_SLUG" "$TASK_SLUG" "$ACTOR" "$TTL" "$INPUT_HASH" <<'PYEOF'
import sqlite3, sys, json, hashlib, time
db, plan_id, plan_slug, task_slug, actor, ttl, input_hash_in = sys.argv[1:8]
ttl = int(ttl)
now = int(time.time())
lease_end = now + ttl

conn = sqlite3.connect(db, timeout=5)
conn.execute("PRAGMA foreign_keys=ON")
conn.row_factory = sqlite3.Row
conn.execute("BEGIN IMMEDIATE")
try:
    task = conn.execute("SELECT id, status FROM tasks WHERE plan_id = ? AND slug = ?", (plan_id, task_slug)).fetchone()
    if not task:
        json.dump({'error': 'task not found: %s' % task_slug}, sys.stdout); conn.rollback(); sys.exit(1)
    if task['status'] in ('approved', 'resolved', 'rejected', 'blocked'):
        json.dump({'error': 'task in terminal status=%s (immutable)' % task['status']}, sys.stdout); conn.rollback(); sys.exit(1)
    # Issue 2: verificar deps blocks dentro de la transaccion
    pending_deps = conn.execute("""
        SELECT dep.slug FROM task_dependencies d
        JOIN tasks dep ON dep.id = d.depends_on_task_id
        WHERE d.task_id = ? AND d.type = 'blocks' AND dep.status NOT IN ('approved', 'resolved')
    """, (task['id'],)).fetchall()
    if pending_deps:
        slugs = [r['slug'] for r in pending_deps]
        json.dump({'error': 'task has pending deps: %s' % ','.join(slugs)}, sys.stdout)
        conn.rollback(); sys.exit(1)

    # Input hash determinista (Issue 3): si caller no lo proveyó, calcular con plan_version
    plan_version = conn.execute("SELECT COALESCE(MAX(version), 0) FROM plan_history WHERE plan_id = ?", (plan_id,)).fetchone()[0]
    if input_hash_in == '__AUTO__':
        h = hashlib.sha256()
        h.update(plan_slug.encode())
        h.update(b'|')
        h.update(task_slug.encode())
        h.update(b'|')
        h.update(actor.encode())
        h.update(b'|v')
        h.update(str(plan_version).encode())
        input_hash = h.hexdigest()
    else:
        input_hash = input_hash_in

    # Buscar claim activo existente
    existing = conn.execute(
        "SELECT id, actor, input_hash, lease_until, status, attempt FROM task_claims "
        "WHERE task_id = ? AND status = 'active'",
        (task['id'],)
    ).fetchone()

    if existing:
        # lease_until es INTEGER, pero rows legacy (pre-0.7.2) pueden ser TEXT datetime → epoch 0 (expired)
        def lease_epoch(v):
            try:
                return int(v)
            except (TypeError, ValueError):
                return 0
        lease_ok = lease_epoch(existing['lease_until']) > now
        if lease_ok and existing['actor'] == actor and existing['input_hash'] == input_hash:
            json.dump({
                'claim_id': existing['id'],
                'idempotent': True,
                'lease_until': existing['lease_until'],
                'attempt': existing['attempt'],
            }, sys.stdout)
            conn.commit(); sys.exit(0)
        if lease_ok:
            json.dump({'error': 'claimed by %s (lease until %s)' % (existing['actor'], existing['lease_until'])}, sys.stdout)
            conn.rollback(); sys.exit(2)
        # Lease expirado: nuevo attempt (Issue 6: historial)
        new_attempt = (conn.execute(
            "SELECT COALESCE(MAX(attempt), 0) + 1 FROM task_claims WHERE task_id = ?",
            (task['id'],)
        ).fetchone()[0])
        # Marcar el activo anterior como expired
        conn.execute("UPDATE task_claims SET status = 'expired', released_at = ? WHERE id = ?",
                     (now, existing['id']))
        cur = conn.execute("""
            INSERT INTO task_claims(task_id, actor, attempt, input_hash, lease_until, status, claimed_at)
            VALUES(?, ?, ?, ?, ?, 'active', ?)
        """, (task['id'], actor, new_attempt, input_hash, lease_end, now))
        claim_id = cur.lastrowid
    else:
        new_attempt = (conn.execute(
            "SELECT COALESCE(MAX(attempt), 0) + 1 FROM task_claims WHERE task_id = ?",
            (task['id'],)
        ).fetchone()[0])
        cur = conn.execute("""
            INSERT INTO task_claims(task_id, actor, attempt, input_hash, lease_until, status, claimed_at)
            VALUES(?, ?, ?, ?, ?, 'active', ?)
        """, (task['id'], actor, new_attempt, input_hash, lease_end, now))
        claim_id = cur.lastrowid

    conn.execute("UPDATE tasks SET status = 'in_progress', owner = ?, started_at = ?, updated_at = ? WHERE id = ?",
                 (actor, now, now, task['id']))
    conn.execute("INSERT INTO audit_log(ts, agent, action, table_name, actor_source) VALUES(datetime('now'), ?, 'claim', 'task_claims', 'helper')",
                 (actor,))
    conn.commit()
    json.dump({'claim_id': claim_id, 'lease_until': lease_end, 'attempt': new_attempt}, sys.stdout)
except Exception as e:
    conn.rollback()
    json.dump({'error': str(e)}, sys.stdout)
    sys.exit(1)
PYEOF
