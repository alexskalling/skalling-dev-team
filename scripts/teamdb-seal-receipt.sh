#!/usr/bin/env bash
# teamdb-seal-receipt.sh — Emite un receipt SELLADO con tree_hash (revisión congelada)
# v0.8.3: congela el hash del árbol que se revisó para que pre-commit verifique
# que los archivos staged son EXACTAMENTE los que se revisaron.
#
# NO confundir con skalling-receipt.sh: este escribe una fila en la tabla
# `receipts` de TeamDB, y es lo que git-gate.py exige para permitir un commit
# (prueba de review). skalling-receipt.sh es un archivo JSON suelto en disco,
# bitácora de trabajo sin relación con el gate de commits.
# Uso: bash teamdb-seal-receipt.sh <task_id> <jhon|luz|humano> [project]
#
# humano: una persona que commitea desde su terminal (sin OpenCode). Mismo
# rigor que jhon (corre el test real sobre lo staged); queda atribuido a
# quien lo hizo. Atajo: skalling-approve.sh.
#
# Camino HUMANO (terminal). Dentro de OpenCode la evidencia la registra el
# motor skalling_workflow (identidad del runtime, no de variables de shell):
# con SKALLING_RUNTIME_AGENT presente este script se niega.
#
# Nunca aprueba por defecto (auditoría externa v0.12.0 #2: sin variables,
# un sello de "luz" quedaba exit 0 con resumen vacío y abría el commit):
#   jhon  corre la verificación real del proyecto; su exit code manda.
#   luz   solo con la evidencia que deja skalling-review.sh.
# Entorno (lo pone skalling-review.sh, nunca el agente):
#   TEAMDB_CLAIM_COMMAND        "review --..." (obligatorio para luz)
#   TEAMDB_CLAIM_EXIT_CODE      exit code de la revisión (obligatorio para luz)
#   TEAMDB_CLAIM_TREE_HASH      hash congelado al empezar la revisión
#   TEAMDB_CLAIM_OUTPUT_SUMMARY resumen de findings (obligatorio para luz)
#   SKALLING_VERIFY_WAIVER      (solo humano, en terminal) motivo para aprobar
#                               sin tests un proyecto que no los tiene
#
# Estados que deja un receipt (columna command + exit_code):
#   verified  jhon corrió el test real del proyecto y pasó (exit 0)
#   failed    el test real corrió y falló (exit != 0)
#   not_run   no hay test configurado: exit 2, command "not_run: ..."; el gate
#             NO lo acepta como aprobación
#   waived    un humano aprobó sin tests: exit 0, command "waived: <motivo>";
#             el gate lo acepta y lo anuncia
#   reviewed  revisión (Luz / skalling-review.sh): exit del review
set -euo pipefail
export PYTHONDONTWRITEBYTECODE=1

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
PROJECT="${3:-$(pwd)}"

if [ -z "$TASK_ID" ]; then
  echo "Uso: bash teamdb-seal-receipt.sh <task_id> <agent> [project]" >&2
  exit 1
fi
if [ -n "${SKALLING_RUNTIME_AGENT:-}" ]; then
  echo "ERROR: dentro de OpenCode la aprobación la registra skalling_workflow (check → approve → complete), no este script. Identidad del runtime: ${SKALLING_RUNTIME_AGENT}." >&2
  exit 2
fi
AGENT="$(printf '%s' "${2:-}" | tr '[:upper:]' '[:lower:]')"
case "$AGENT" in
  jhon|luz|humano) ;;
  *) echo "ERROR: solo jhon (verificación real), luz (revisión real) o humano (desde una terminal) sellan; recibido: '${2:-}'" >&2; exit 2 ;;
esac
if [ "$AGENT" = "luz" ]; then
  case "${TEAMDB_CLAIM_COMMAND:-}" in
    "review --"*) ;;
    *) echo "ERROR: luz sella solo la evidencia de skalling-review.sh; correr la revisión, no sellar a mano." >&2; exit 2 ;;
  esac
  if [ -z "${TEAMDB_CLAIM_EXIT_CODE:-}" ] || [ -z "${TEAMDB_CLAIM_OUTPUT_SUMMARY:-}" ]; then
    echo "ERROR: sello de luz sin resultado ni resumen de la revisión; no se aprueba sin evidencia." >&2
    exit 2
  fi
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

# Identidad del candidato: hash del diff staged (mismo algoritmo que
# scripts/hooks/git-gate.py). Se calcula ANTES y DESPUÉS de verificar: una
# aprobación no puede transferirse a contenido que cambió mientras corría el
# test (otro agente o proceso stageando o editando en paralelo).
staged_hash() {
  local diff_text
  diff_text="$(git -C "$PROJECT" diff --cached -- . ':(exclude)db/teamdb/team.dump.sql')"
  [ -n "$diff_text" ] || return 1
  printf '%s' "$diff_text" | shasum -a 256 | cut -c1-16
}
unstaged_tracked() {
  git -C "$PROJECT" diff --name-only -- . ':(exclude)db/teamdb/team.dump.sql'
}

# Lock file para evitar race conditions entre agentes
LOCK_DIR="$PROJECT/.opencode/context/.locks/team"
mkdir -p "$(dirname "$LOCK_DIR")" 2>/dev/null || true
if ! teamdb_lock "$LOCK_DIR" 10; then
  exit 1
fi
trap 'teamdb_unlock "$LOCK_DIR"' EXIT

COMMAND="${TEAMDB_CLAIM_COMMAND:-}"
EXIT_CODE="${TEAMDB_CLAIM_EXIT_CODE:-}"

# Sanitizar surrogate code points (U+D800-U+DFFF): Python 3.14's os.fsencode()
# en subprocess.run/fork_exec rechaza strings con surrogates, y JSON encoding
# no puede UTF-8-encodearlos. El reemplazo es U+FFFD (Unicode replacement char),
# legible y reversible. Solo se sanitiza TEAMDB_CLAIM_OUTPUT_SUMMARY porque es
# la única variable que callers externos pueden setear con contenido arbitrario;
# los otros valores son generados internamente por el script.
if [ -n "${TEAMDB_CLAIM_OUTPUT_SUMMARY:-}" ]; then
  SUMMARY="$(python3 -c "
import sys, re
raw = sys.argv[1]
clean = re.sub(r'[\ud800-\udfff]', '\ufffd', raw)
sys.stdout.write(clean)
" "$TEAMDB_CLAIM_OUTPUT_SUMMARY")"
else
  SUMMARY=""
fi

# jhon es "test verifier": su trabajo es ejecutar comprobaciones
# independientes, no confiar en que quien lo invocó ya las corrió. Antes, un
# receipt de jhon aceptaba el exit code que el caller pasara por variable de
# entorno (default 0) sin correr nada real. Acá, si el proyecto tiene un
# comando de test real configurado (project.yaml, nunca inventado), se corre
# de verdad y SU exit code manda — no el que haya puesto el caller. Si no hay
# comando configurado, se sella igual (no podemos bloquear para siempre un
# proyecto sin tests) pero queda anotado sin ambigüedad, nunca indistinguible
# de un test que sí corrió y pasó.
if [ "$AGENT" = "jhon" ] || [ "$AGENT" = "humano" ]; then
  # skalling-verify.sh corre sobre el WORKING TREE, pero lo que este script
  # sella es el hash de lo STAGED (git diff --cached, más abajo). Si hay
  # cambios sin stagear en archivos trackeados, el test real puede estar
  # evaluando contenido DISTINTO al que efectivamente quedaría commiteado
  # (por ejemplo: se stageó código malo, después se sobreescribió el archivo
  # con código bueno sin volver a hacer git add) -- el receipt quedaría
  # sellado para código que nunca se probó. Ante la duda, bloquear: exigir
  # que el working tree coincida con el índice antes de correr la
  # verificación real.
  UNSTAGED="$(unstaged_tracked)"
  if [ -n "$UNSTAGED" ]; then
    echo "ERROR: hay cambios sin stagear en archivos trackeados; el test real correría sobre contenido distinto al que queda staged. Hacer 'git add' de todo (o descartar lo suelto) antes de sellar un receipt de jhon:" >&2
    echo "$UNSTAGED" >&2
    exit 1
  fi
  if ! CANDIDATE_BEFORE="$(staged_hash)"; then
    echo "ERROR: nada que sellar — no hay cambios staged. No modificar historia para fabricar evidencia." >&2
    exit 1
  fi
  # Un hash provisto por el caller (skalling-review.sh lo congela al empezar)
  # tiene que ser el mismo candidato que jhon va a probar.
  if [ -n "${TEAMDB_CLAIM_TREE_HASH:-}" ] && [ "$TEAMDB_CLAIM_TREE_HASH" != "$CANDIDATE_BEFORE" ]; then
    echo "ERROR: el hash pedido ($TEAMDB_CLAIM_TREE_HASH) no es el candidato staged actual ($CANDIDATE_BEFORE); jhon solo sella lo que prueba." >&2
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
  # Keep failures visible to the caller; the bounded DB summary alone can
  # discard the first failing suite and force a costly diagnostic rerun.
  if [ "$VERIFY_RC" != "0" ]; then
    cat "$VERIFY_OUT_FILE" >&2
  else
    tail -n 5 "$VERIFY_OUT_FILE" >&2
  fi
  VERIFY_OUT="$(tail -c 4000 "$VERIFY_OUT_FILE")"  # lens:ok: output_summary no es una columna sin limite, evita filas gigantes
  # El candidato tiene que ser el mismo antes y después del test: mismo diff
  # staged y working tree todavía igual al índice. Si no, lo que pasó el test
  # no es lo que se sellaría.
  CANDIDATE_AFTER="$(staged_hash || true)"
  UNSTAGED_AFTER="$(unstaged_tracked)"
  if [ "$CANDIDATE_AFTER" != "$CANDIDATE_BEFORE" ] || [ -n "$UNSTAGED_AFTER" ]; then
    echo "ERROR: el candidato cambió mientras corría la verificación (antes $CANDIDATE_BEFORE, después ${CANDIDATE_AFTER:-vacío}${UNSTAGED_AFTER:+, con cambios sin stagear}). No se sella: volver a verificar sobre el contenido final." >&2
    exit 1
  fi
  TEAMDB_CLAIM_TREE_HASH="$CANDIDATE_BEFORE"
  if [ "$VERIFY_RC" = "2" ]; then
    # Sin test configurado no hay verificación: nunca el mismo estado que un
    # test que corrió y pasó. Solo un humano puede dispensarlo, con motivo.
    if [ -n "${SKALLING_VERIFY_WAIVER:-}" ]; then
      COMMAND="waived: ${SKALLING_VERIFY_WAIVER}"
      EXIT_CODE=0
      SUMMARY="WAIVED: aprobado sin tests por decisión humana (${SKALLING_VERIFY_WAIVER}). $VERIFY_OUT"
      echo "WARN: receipt waived — sin test ejecutado, aprobado por motivo explícito: $SKALLING_VERIFY_WAIVER" >&2
    else
      COMMAND="not_run: skalling-verify.sh sin comando de test configurado"
      EXIT_CODE=2
      SUMMARY="NOT_RUN: no hay testing.unit.command en project.yaml; jhon no pudo correr una verificación real. $VERIFY_OUT"
      echo "WARN: receipt not_run — no hay tests configurados; el gate no lo acepta. Configurar testing.unit.command, pedir revisión de Luz, o que un humano defina SKALLING_VERIFY_WAIVER=\"motivo\" al sellar." >&2
    fi
  else
    COMMAND="skalling-verify.sh (test real del proyecto)"
    # Un review con blockers (exit del caller != 0) no se lava con tests verdes.
    if [ "$VERIFY_RC" = "0" ] && [ -n "$EXIT_CODE" ] && [ "$EXIT_CODE" != "0" ]; then
      COMMAND="${TEAMDB_CLAIM_COMMAND} + skalling-verify.sh"
    else
      EXIT_CODE="$VERIFY_RC"
    fi
    SUMMARY="$VERIFY_OUT"
    if [ "$VERIFY_RC" != "0" ]; then
      echo "WARN: el test real del proyecto falló (exit $VERIFY_RC); el receipt queda sellado con esa falla — in_review->approved no va a encontrar un receipt exit_code=0 de jhon para esto." >&2
    fi
  fi
fi

# Evidence refers to the staged candidate, not unstaged work or elapsed time.
TREE_HASH="${TEAMDB_CLAIM_TREE_HASH:-}"
if [ -z "$TREE_HASH" ]; then
  if ! TREE_HASH="$(staged_hash)"; then
    echo "ERROR: nada que sellar — no hay cambios staged. No modificar historia para fabricar evidencia." >&2
    exit 1
  fi
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
