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

# Bug real (2026-09-13, proyecto Survan): un agente cerró con
# `skalling-metrics.sh finish req-x SUCCESS` (mayusculas) y "summary"
# comparaba contra 'success' en minusculas -- la fila quedaba completed=1
# pero success=0. Dos fixes independientes:
#
# 1. Lectura: "summary" compara con LOWER(outcome), asi que una fila ya
#    escrita en una DB real con otra casing (como la del caso real) igual
#    cuenta como success.
sqlite3 "$DB" <<'SQL'
INSERT INTO workflow_metrics
  (request_id,risk_level,route,agents_count,handoffs,permission_prompts,context_bytes,started_at,completed_at,duration_ms,outcome)
VALUES
  ('legacy-upper','low','FAST-TRACK',2,0,0,0,'2026-01-01','2026-01-01',600,'SUCCESS');
SQL
SUMMARY_LEGACY="$(bash "$ROOT/scripts/skalling-metrics.sh" summary "$FIXTURE")"
# avg_handoffs=(1+2+0+0)/4=0.75, avg_permissions=(0+1+0+0)/4=0.25: valores
# redondeados a 2 decimales, no truncados a entero (ver fix de arriba).
EXPECTED_LEGACY='route=FAST-TRACK risk=low runs=4 completed=3 success=2'
EXPECTED_LEGACY+=' avg_duration_ms=333 avg_handoffs=0.75 avg_permissions=0.25 avg_context_bytes=750'
grep -Fqx "$EXPECTED_LEGACY" <<< "$SUMMARY_LEGACY"
printf 'PASS: fila ya escrita con outcome en mayusculas cuenta como success (LOWER en summary)\n'

# 2. Escritura: "finish" normaliza el outcome a minusculas antes de
#    guardarlo, para que datos nuevos no dependan de la casing que use
#    cada agente al invocarlo.
bash "$ROOT/scripts/skalling-metrics.sh" finish pending SUCCESS "$FIXTURE" >/dev/null
STORED_OUTCOME="$(sqlite3 "$DB" "SELECT outcome FROM workflow_metrics WHERE request_id='pending'")"
[ "$STORED_OUTCOME" = "success" ]
printf 'PASS: finish normaliza outcome a minusculas al escribir\n'
