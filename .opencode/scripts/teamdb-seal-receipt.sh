#!/usr/bin/env bash
# teamdb-seal-receipt.sh — Emite un receipt SELLADO con tree_hash (revisión congelada)
# v0.8.3: congela el hash del árbol que se revisó para que pre-commit verifique
# que los archivos staged son EXACTAMENTE los que se revisaron.
#
# NO confundir con skalling-receipt.sh: este escribe una fila en la tabla
# `receipts` de TeamDB, y es lo que git-gate.py exige para permitir un commit
# (prueba de review). skalling-receipt.sh es un archivo JSON suelto en disco,
# bitácora de trabajo sin relación con el gate de commits.
# Uso: bash teamdb-seal-receipt.sh <task_id> <agent> [project]
# Entorno (patrón claim-task.sh):
#   TEAMDB_CLAIM_COMMAND        comando registrado (default: review-seal)
#   TEAMDB_CLAIM_EXIT_CODE      exit code del comando (default: 0)
#   TEAMDB_CLAIM_TREE_HASH      hash a sellar (override del cálculo automático)
#   TEAMDB_CLAIM_OUTPUT_SUMMARY resumen JSON de findings (opcional)
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# shellcheck disable=SC1091
if [ -f "$SCRIPT_DIR/lib-teamdb.sh" ]; then
  source "$SCRIPT_DIR/lib-teamdb.sh"
elif [ -f "$SCRIPT_DIR/lib/lib-teamdb.sh" ]; then
  # shellcheck disable=SC1091
  source "$SCRIPT_DIR/lib/lib-teamdb.sh"
else
  echo "ERROR: lib-teamdb.sh no encontrado" >&2
  exit 1
fi

TASK_ID="${1:-}"
AGENT="${2:-luz}"
PROJECT="${3:-$(pwd)}"

if [ -z "$TASK_ID" ]; then
  echo "Uso: bash teamdb-seal-receipt.sh <task_id> <agent> [project]" >&2
  exit 1
fi

DB="$(teamdb_project_path "$PROJECT")"
if [ ! -f "$DB" ]; then
  echo "ERROR: DB no existe: $DB" >&2
  exit 1
fi

# Si la DB es vieja (pre-migración) sin la columna tree_hash, aplicar las
# migraciones SQL pendientes ANTES de tomar el lock (teamdb-init usa el mismo
# lock y no puede ejecutarse mientras lo tengamos nosotros).
has_tree_hash() {
  [ "$(sqlite3 "$1" "SELECT COUNT(*) FROM pragma_table_info('receipts') WHERE name='tree_hash'" 2>/dev/null || echo 0)" = "1" ]
}

if ! has_tree_hash "$DB"; then
  echo "WARN: receipts sin columna tree_hash (DB pre-migración); aplicando migrations..." >&2
  for candidate in "$PROJECT/scripts/teamdb-init.sh" "$SCRIPT_DIR/teamdb-init.sh"; do
    if [ -f "$candidate" ]; then
      if bash "$candidate" "$PROJECT" >/dev/null 2>&1; then
        break
      fi
    fi
  done
fi

# Lock file para evitar race conditions entre agentes
LOCK_DIR="$PROJECT/.opencode/context/.locks/team"
mkdir -p "$(dirname "$LOCK_DIR")" 2>/dev/null || true
if ! teamdb_lock "$LOCK_DIR" 10; then
  exit 1
fi
trap 'teamdb_unlock "$LOCK_DIR"' EXIT

COMMAND="${TEAMDB_CLAIM_COMMAND:-review-seal}"
EXIT_CODE="${TEAMDB_CLAIM_EXIT_CODE:-0}"
SUMMARY="${TEAMDB_CLAIM_OUTPUT_SUMMARY:-}"

# jhon es "test verifier": su trabajo es ejecutar comprobaciones
# independientes, no confiar en que quien lo invocó ya las corrió. Antes, un
# receipt de jhon aceptaba el exit code que el caller pasara por variable de
# entorno (default 0) sin correr nada real. Acá, si el proyecto tiene un
# comando de test real configurado (project.yaml, nunca inventado), se corre
# de verdad y SU exit code manda — no el que haya puesto el caller. Si no hay
# comando configurado, se sella igual (no podemos bloquear para siempre un
# proyecto sin tests) pero queda anotado sin ambigüedad, nunca indistinguible
# de un test que sí corrió y pasó.
if [ "$AGENT" = "jhon" ]; then
  # skalling-verify.sh corre sobre el WORKING TREE, pero lo que este script
  # sella es el hash de lo STAGED (git diff --cached, más abajo). Si hay
  # cambios sin stagear en archivos trackeados, el test real puede estar
  # evaluando contenido DISTINTO al que efectivamente quedaría commiteado
  # (por ejemplo: se stageó código malo, después se sobreescribió el archivo
  # con código bueno sin volver a hacer git add) -- el receipt quedaría
  # sellado para código que nunca se probó. Ante la duda, bloquear: exigir
  # que el working tree coincida con el índice antes de correr la
  # verificación real.
  UNSTAGED="$(git -C "$PROJECT" diff --name-only -- . ':(exclude)db/teamdb/team.dump.sql')"
  if [ -n "$UNSTAGED" ]; then
    echo "ERROR: hay cambios sin stagear en archivos trackeados; el test real correría sobre contenido distinto al que queda staged. Hacer 'git add' de todo (o descartar lo suelto) antes de sellar un receipt de jhon:" >&2
    echo "$UNSTAGED" >&2
    exit 1
  fi
  VERIFY_OUT_FILE="$(mktemp)"
  trap 'rm -f "$VERIFY_OUT_FILE"' EXIT  # lens:ok: VERIFY_OUT_FILE viene de mktemp, ruta propia, nunca input externo
  # El test real de un proyecto puede tardar bastante mas que el timeout del
  # lock (10s) -- soltarlo mientras corre, para no dejar a los otros 7
  # agentes bloqueados escribiendo en TeamDB durante ese tiempo. No hace
  # falta el lock para correr un comando externo de solo lectura sobre el
  # working tree; se vuelve a tomar recien antes de escribir el receipt.
  teamdb_unlock "$LOCK_DIR"
  set +e
  bash "$SCRIPT_DIR/skalling-verify.sh" "$PROJECT" > "$VERIFY_OUT_FILE" 2>&1
  VERIFY_RC=$?
  set -e
  if ! teamdb_lock "$LOCK_DIR" 10; then
    echo "ERROR: no se pudo re-tomar el lock para sellar el receipt tras la verificación" >&2
    exit 1
  fi
  trap 'rm -f "$VERIFY_OUT_FILE"; teamdb_unlock "$LOCK_DIR"' EXIT  # lens:ok: VERIFY_OUT_FILE viene de mktemp, ruta propia, nunca input externo
  VERIFY_OUT="$(tail -c 4000 "$VERIFY_OUT_FILE")"  # lens:ok: output_summary no es una columna sin limite, evita filas gigantes
  if [ "$VERIFY_RC" = "2" ]; then
    SUMMARY="SIN-CONFIGURAR: no hay testing.unit.command en project.yaml; jhon no pudo correr una verificación real. ${SUMMARY}"
  else
    COMMAND="skalling-verify.sh (test real del proyecto)"
    EXIT_CODE="$VERIFY_RC"
    SUMMARY="$VERIFY_OUT"
    if [ "$VERIFY_RC" != "0" ]; then
      echo "WARN: el test real del proyecto falló (exit $VERIFY_RC); el receipt queda sellado con esa falla — in_review->approved no va a encontrar un receipt exit_code=0 de jhon para esto." >&2
    fi
  fi
fi

# Evidence refers to the staged candidate, not unstaged work or elapsed time.
TREE_HASH="${TEAMDB_CLAIM_TREE_HASH:-}"
if [ -z "$TREE_HASH" ]; then
  DIFF_TEXT="$(git -C "$PROJECT" diff --cached -- . ':(exclude)db/teamdb/team.dump.sql')"
  if [ -z "$DIFF_TEXT" ]; then
    echo "ERROR: nada que sellar — no hay cambios staged. No modificar historia para fabricar evidencia." >&2
    exit 1
  fi
  TREE_HASH="$(printf '%s' "$DIFF_TEXT" | shasum -a 256 | cut -c1-16)"
fi

RECEIPT_ID="rcpt_$(date +%s)_$$"

# INSERT con parámetros vinculados (teamdb_exec.py, "camino activo" del repo).
if has_tree_hash "$DB" && [ -n "$TREE_HASH" ]; then
  if ! OUT="$(teamdb_exec_write "$DB" \
    "INSERT INTO receipts (id, task_id, agent, command, exit_code, output_summary, ts, tree_hash) VALUES (?,?,?,?,?,?,datetime('now'),?)" \
    "$RECEIPT_ID" "$TASK_ID" "$AGENT" "$COMMAND" "$EXIT_CODE" "$SUMMARY" "$TREE_HASH" 2>&1)"; then
    echo "ERROR: no se pudo sellar receipt ($OUT)" >&2
    exit 1
  fi
  echo "OK: receipt sellado $RECEIPT_ID (tree_hash=$TREE_HASH)"
else
  echo "WARN: no se pudo migrar tree_hash; receipt emitido SIN sellar" >&2
  if ! OUT="$(teamdb_exec_write "$DB" \
    "INSERT INTO receipts (id, task_id, agent, command, exit_code, output_summary, ts) VALUES (?,?,?,?,?,?,datetime('now'))" \
    "$RECEIPT_ID" "$TASK_ID" "$AGENT" "$COMMAND" "$EXIT_CODE" "$SUMMARY" 2>&1)"; then
    echo "ERROR: no se pudo emitir receipt ($OUT)" >&2
    exit 1
  fi
  echo "OK: receipt $RECEIPT_ID (sin tree_hash)"
fi

# El receipt es evidencia local. Exportar memoria es una operación independiente.

exit 0
