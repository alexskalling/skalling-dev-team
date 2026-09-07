#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT
export HOME="$TMP/home"
PROJECT="$TMP/project"
mkdir -p "$HOME/.config/opencode" "$PROJECT/.opencode/context"
sqlite3 "$PROJECT/.opencode/context/team.db" < "$ROOT/sql/project-schema.sql"
sqlite3 "$PROJECT/.opencode/context/team.db" <<'SQL'
INSERT INTO concepts(slug,title,body_md,category,updated_at) VALUES('auth','Autenticación','JWT y sesiones','modulo',datetime('now'));
INSERT INTO concepts(slug,title,body_md,category,updated_at) VALUES('project-summary','Resumen del proyecto','Sistema de agentes Skalling','project-summary',datetime('now'));
INSERT INTO decisions(slug,title,body_md,status) VALUES('jwt','Usar JWT','Refresh rotativo','accepted');
INSERT INTO known_problems(slug,title,symptom_md,status) VALUES('clock','Desfase de reloj','Expiración anticipada','open');
INSERT INTO schema_meta(key,value) VALUES('project_readiness','ready');
SQL

assert_contains() {
  local description="$1" output="$2" expected="$3"
  case "$output" in *"$expected"*) echo "✓ $description" ;; *) echo "✗ $description: $output" >&2; exit 1 ;; esac
}

LOW="$(bash "$ROOT/scripts/skalling-route.sh" classify --project "$PROJECT" --risk low --scope local --clarity clear --kind code)"
MEDIUM="$(bash "$ROOT/scripts/skalling-route.sh" classify --project "$PROJECT" --risk medium --scope module --clarity clear --kind code)"
HIGH="$(bash "$ROOT/scripts/skalling-route.sh" classify --project "$PROJECT" --risk high --clarity ambiguous --kind code)"
assert_contains "bajo riesgo usa equipo mínimo" "$LOW" 'Alex → Teo → Jhon'
assert_contains "riesgo medio evita ciclo completo" "$MEDIUM" 'Alex → Sol → Teo → Jhon'
assert_contains "alto riesgo usa ciclo completo" "$HIGH" 'Alex → Pol → Sol → Teo → Jhon → Luz → Pau'

CAPSULE="$(bash "$ROOT/scripts/teamdb-context.sh" for-request "corregir autenticación JWT" --max-bytes=4096 "$PROJECT")"
assert_contains "cápsula recupera memoria pertinente" "$CAPSULE" 'Autenticación'
assert_contains "cápsula conserva resumen general" "$CAPSULE" 'project-summary'
[ "$(printf '%s' "$CAPSULE" | wc -c | tr -d ' ')" -le 4096 ] || { echo "✗ cápsula excede presupuesto" >&2; exit 1; }
echo "✓ cápsula respeta presupuesto de bytes"

bash "$ROOT/scripts/skalling-metrics.sh" start req-1 low "$PROJECT" FAST-TRACK 3 >/dev/null
bash "$ROOT/scripts/skalling-metrics.sh" event req-1 handoff 1 "$PROJECT" >/dev/null
bash "$ROOT/scripts/skalling-metrics.sh" event req-1 context_bytes 2048 "$PROJECT" >/dev/null
bash "$ROOT/scripts/skalling-metrics.sh" finish req-1 success "$PROJECT" >/dev/null
METRICS="$(bash "$ROOT/scripts/skalling-metrics.sh" report "$PROJECT")"
assert_contains "métricas registran handoffs" "$METRICS" 'handoffs=1'
assert_contains "métricas registran contexto" "$METRICS" 'context_bytes=2048'
assert_contains "métricas registran ruta" "$METRICS" 'route=FAST-TRACK'
assert_contains "métricas registran agentes" "$METRICS" 'agents=3'

MD_COUNT="$(find "$PROJECT" -name '*.md' -type f | wc -l | tr -d ' ')"
[ "$MD_COUNT" = "0" ] || { echo "✗ flujo creó Markdown interno" >&2; exit 1; }
echo "✓ flujo no crea Markdown interno"

grep -q 'Clasificación por riesgo' "$ROOT/agents-base/Alex.md" || { echo "✗ Alex no exige clasificación por riesgo" >&2; exit 1; }
grep -q 'for-request' "$ROOT/agents-base/Alex.md" || { echo "✗ Alex no prepara cápsula por pedido" >&2; exit 1; }
grep -q 'Verificación proporcional' "$ROOT/agents-base/Jhon.md" || { echo "✗ Jhon no verifica proporcionalmente" >&2; exit 1; }
grep -q 'Cierre ligero' "$ROOT/agents-base/Pau.md" || { echo "✗ Pau no tiene cierre ligero" >&2; exit 1; }
grep -q '"risk_level"' "$ROOT/templates/handoff.schema.json" || { echo "✗ handoff no transporta riesgo" >&2; exit 1; }
grep -q '"context_capsule"' "$ROOT/templates/handoff.schema.json" || { echo "✗ handoff no transporta cápsula" >&2; exit 1; }
echo "✓ contratos de agentes y handoff incorporan el flujo adaptativo"
