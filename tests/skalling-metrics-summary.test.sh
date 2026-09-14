#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
FIXTURE="$(mktemp -d)"
trap '[ -n "$FIXTURE" ] && [ -d "$FIXTURE" ] && rm -rf -- "$FIXTURE"' EXIT
mkdir -p "$FIXTURE/.opencode/context"
DB="$FIXTURE/.opencode/context/team.db"

sqlite3 "$DB" < "$ROOT/sql/project-schema.sql"
sqlite3 "$DB" <<'SQL'
INSERT INTO workflow_metrics
  (request_id,risk_level,route,agents_count,handoffs,permission_prompts,context_bytes,started_at,completed_at,duration_ms,outcome)
VALUES
  ('fast-ok','low','FAST-TRACK',2,1,0,1200,'2026-01-01','2026-01-01',100,'success'),
  ('fast-fail','low','FAST-TRACK',2,2,1,1800,'2026-01-01','2026-01-01',300,'failed'),
  ('standard-ok','medium','PLAN-TEO-JHON',4,3,2,9000,'2026-01-01','2026-01-01',900,'success'),
  ('pending','low','FAST-TRACK',2,0,0,0,'2026-01-01',NULL,NULL,NULL);
SQL

SUMMARY="$(bash "$ROOT/scripts/skalling-metrics.sh" summary "$FIXTURE")"

# avg_handoffs/avg_permissions se redondean a 2 decimales (no se truncan a
# entero): FAST-TRACK trae permission_prompts=0,1,0 → avg=0.33, no 0 — una
# fricción real de "1 de cada 3" no debe desaparecer en el reporte.
grep -Fqx 'route=FAST-TRACK risk=low runs=3 completed=2 success=1 avg_duration_ms=200 avg_handoffs=1.0 avg_permissions=0.33 avg_context_bytes=1000' <<< "$SUMMARY"
grep -Fqx 'route=PLAN-TEO-JHON risk=medium runs=1 completed=1 success=1 avg_duration_ms=900 avg_handoffs=3.0 avg_permissions=2.0 avg_context_bytes=9000' <<< "$SUMMARY"
printf 'PASS: resumen de métricas agrupa velocidad, fricción y resultado sin truncar promedios fraccionarios\n'
