#!/usr/bin/env bash
# skalling-approve.sh — camino HUMANO para commitear en un proyecto con Skalling.
#
# El hook de Git exige una verificación aprobada del candidato exacto staged.
# Dentro de OpenCode la registra skalling_workflow; una persona que commitea
# desde su terminal (o su IDE) corre esto: ejecuta el test real del proyecto
# (testing.unit de .opencode/project.yaml) sobre lo staged y, si pasa, deja el
# receipt que habilita `git commit`. Queda atribuido a "humano", no a Jhon.
#
# Uso: bash .opencode/scripts/skalling-approve.sh [proyecto]
#   Sin tests configurados: SKALLING_VERIFY_WAIVER="motivo" bash ... aprueba
#   sin tests, y el hook lo anuncia en cada commit.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT="${1:-$(git rev-parse --show-toplevel 2>/dev/null || pwd)}"

if [ -n "${SKALLING_RUNTIME_AGENT:-}" ]; then
  echo "ERROR: esto es para personas en su terminal. Dentro de OpenCode la aprobación la registra skalling_workflow (Jhon o Luz)." >&2
  exit 2
fi
if git -C "$PROJECT" diff --cached --quiet -- . ':(exclude)db/teamdb/team.dump.sql'; then
  echo "Nada staged para aprobar. Primero: git add <archivos>" >&2
  exit 1
fi

TASK_ID="humano-$(date +%Y%m%d%H%M%S)"
echo "Corriendo los tests del proyecto sobre lo staged (esto habilita el commit si pasan)..." >&2
if bash "$SCRIPT_DIR/teamdb-seal-receipt.sh" "$TASK_ID" humano "$PROJECT"; then
  RC="$(sqlite3 "$PROJECT/.opencode/context/team.db" \
    "SELECT exit_code FROM receipts WHERE task_id='$TASK_ID' ORDER BY ts DESC LIMIT 1" 2>/dev/null || echo 1)"  # lens:ok: TASK_ID lo genera este script con date, nunca input externo
  if [ "$RC" = "0" ]; then
    echo "OK: aprobado. Ya podés hacer git commit (sin --no-verify)." >&2
    exit 0
  fi
  echo "Los tests fallaron o no están configurados: el commit sigue bloqueado. Ver el detalle arriba." >&2
  exit 1
fi
exit 1
