#!/usr/bin/env bash
# teamdb-attempt.sh — Ledger de intentos de implementación por change (sdd-attempt simplificado)
# Registra en la tabla `attempts` cuántos intentos lleva un change, el tope
# (max_attempts / max_changed_lines) y el estado de la puerta.
#
# Subcomandos:
#   acquire --change <c> --request-id <id> [--work-unit <w>] [--evidence-goal <g>]
#           [--max-attempts <n>] [--max-changed-lines <n>] [project]
#     → imprime `state=proceed token=<tok>` si hay presupuesto, o
#       `state=blocked <razón>` si no.
#   settle --token <tok> --request-id <id> --outcome <ok|fail|partial|abandoned>
#          [--evidence <text>] [project]
#     → cierra el intento; imprime el estado resultante (proceed|blocked|complete).
#   status [--change <c>] [project]
#     → lista intentos (todos o filtrados por change).
#
# Decisiones de diseño:
#   - acquire BLOQUEADO NO inserta fila: el ledger solo guarda intentos reales;
#     las peticiones bloqueadas se reportan por stdout y se van.
#   - El tope de un change es max_attempts del intento MÁS RECIENTE del change
#     (o el default 3 si todavía no hay ninguno). Un acquire en curso
#     (state=proceed) del mismo change también bloquea (evita 2 agentes en paralelo).
#   - settle incrementa attempts_used SOLO si outcome != abandoned.
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

usage() {
  cat <<'EOF'
Uso:
  teamdb-attempt.sh acquire --change <c> --request-id <id> [--work-unit <w>] [--evidence-goal <g>] [--max-attempts <n>] [--max-changed-lines <n>] [project]
  teamdb-attempt.sh settle --token <tok> --request-id <id> --outcome ok|fail|partial|abandoned [--evidence <text>] [project]
  teamdb-attempt.sh status [--change <c>] [project]
EOF
}

# setup_db: toma el lock y valida la DB (PROJECT debe estar definido antes).
setup_db() {
  LOCK_DIR="$PROJECT/.opencode/context/.locks/team"
  mkdir -p "$(dirname "$LOCK_DIR")" 2>/dev/null || true
  if ! teamdb_lock "$LOCK_DIR" 10; then
    exit 1
  fi
  trap 'teamdb_unlock "$LOCK_DIR"' EXIT
  DB="$(teamdb_project_path "$PROJECT")"
  if [ ! -f "$DB" ]; then
    echo "ERROR: DB no existe: $DB (corré bash scripts/teamdb-init.sh <proyecto>)" >&2
    exit 1
  fi
}

cmd_acquire() {
  local change="" request_id="" work_unit="" evidence_goal="" max_attempts="3" max_changed_lines="400"
  local token=""
  while [ "$#" -gt 0 ]; do
    case "$1" in
      --change) change="${2:-}"; shift 2 ;;
      --request-id) request_id="${2:-}"; shift 2 ;;
      --work-unit) work_unit="${2:-}"; shift 2 ;;
      --evidence-goal) evidence_goal="${2:-}"; shift 2 ;;
      --max-attempts) max_attempts="${2:-}"; shift 2 ;;
      --max-changed-lines) max_changed_lines="${2:-}"; shift 2 ;;
      --help|-h) usage; exit 0 ;;
      *) PROJECT="$1"; shift ;;
    esac
  done
  [ -n "$change" ] || { echo "ERROR: acquire requiere --change <c>" >&2; usage >&2; exit 2; }
  [ -n "$request_id" ] || { echo "ERROR: acquire requiere --request-id <id>" >&2; usage >&2; exit 2; }
  setup_db

  # Puerta de entrada (fail-open): si no hay presupuesto, NO se inserta nada.
  # 1) Ya hay un intento en curso del mismo change (proceed) → no duplicar.
  ACTIVE="$(teamdb_exec_value "$DB" "SELECT COUNT(*) FROM attempts WHERE change_name=? AND state='proceed'" "$change")"
  if [ "${ACTIVE:-0}" != "0" ]; then
    echo "state=blocked (change '$change' ya tiene un intento en curso)"
    exit 0
  fi
  # 2) Suma de intentos usados del change >= tope del intento más reciente.
  USED="$(teamdb_exec_value "$DB" "SELECT COALESCE(SUM(attempts_used), 0) FROM attempts WHERE change_name=?" "$change")"
  LAST_MAX="$(teamdb_exec_value "$DB" "SELECT max_attempts FROM attempts WHERE change_name=? ORDER BY id DESC LIMIT 1" "$change")"
  [ -n "$LAST_MAX" ] || LAST_MAX="$max_attempts"
  if [ "${USED:-0}" -ge "$LAST_MAX" ]; then
    echo "state=blocked (change '$change' agotó su presupuesto: $USED/$LAST_MAX intentos usados)"
    exit 0
  fi

  # Token random (macOS/Linux sin dependencias): od sobre /dev/urandom.
  token="atmp_$(od -An -N8 -tx1 /dev/urandom 2>/dev/null | tr -d ' \n')"
  [ -n "${token#atmp_}" ] || token="atmp_$(date +%s)_$$"

  if ! OUT="$(teamdb_exec_write "$DB" \
    "INSERT INTO attempts (token, change_name, request_id, work_unit, evidence_goal, max_attempts, max_changed_lines, state) VALUES (?,?,?,?,?,?,?,'proceed')" \
    "$token" "$change" "$request_id" "$work_unit" "$evidence_goal" "$max_attempts" "$max_changed_lines" 2>&1)"; then
    echo "ERROR: no se pudo registrar el intento ($OUT)" >&2
    exit 1
  fi
  # FASE 1: dump fresco post-escritura
  teamdb_refresh_dump "$PROJECT" >/dev/null 2>&1 || true
  echo "state=proceed token=$token"
  exit 0
}

cmd_settle() {
  local token="" request_id="" outcome="" evidence=""
  while [ "$#" -gt 0 ]; do
    case "$1" in
      --token) token="${2:-}"; shift 2 ;;
      --request-id) request_id="${2:-}"; shift 2 ;;
      --outcome) outcome="${2:-}"; shift 2 ;;
      --evidence) evidence="${2:-}"; shift 2 ;;
      --help|-h) usage; exit 0 ;;
      *) PROJECT="$1"; shift ;;
    esac
  done
  [ -n "$token" ] || { echo "ERROR: settle requiere --token <tok>" >&2; usage >&2; exit 2; }
  case "$outcome" in
    ok|fail|partial|abandoned) ;;
    *) echo "ERROR: --outcome debe ser ok|fail|partial|abandoned (recibido: '${outcome:-}')" >&2; exit 2 ;;
  esac
  setup_db

  # El token debe existir y pertenecer a la misma request (traza end-to-end).
  ROW_REQUEST="$(teamdb_exec_value "$DB" "SELECT request_id FROM attempts WHERE token=?" "$token")"
  if [ -z "$ROW_REQUEST" ]; then
    echo "ERROR: token no encontrado: $token" >&2
    exit 1
  fi
  if [ -n "$request_id" ] && [ "$ROW_REQUEST" != "$request_id" ]; then
    echo "ERROR: request_id no coincide con el del intento (registrado: $ROW_REQUEST)" >&2
    exit 1
  fi

  # ── Idempotencia del settle (audit v0.8.3) ──
  # Un replay del MISMO token con el MISMO outcome NO debe volver a incrementar
  # attempts_used: un retry tras timeout agotaba el presupuesto del change
  # (reproducido 1/3 → 2/3 → 3/3 con el mismo token+request).
  #   - complete + mismo outcome   → replay legítimo: no incrementa, exit 0.
  #   - complete + outcome distinto → contradicción de estados: ERROR, exit 1.
  #   - proceed → UPDATE condicional (WHERE state='proceed'); si changes()=0
  #     otro proceso ganó la race y se re-aplica el criterio sin incrementar.
  CUR_STATE="$(teamdb_exec_value "$DB" "SELECT state FROM attempts WHERE token=?" "$token")"
  if [ "$CUR_STATE" = "complete" ]; then
    CUR_OUTCOME="$(teamdb_exec_value "$DB" "SELECT outcome FROM attempts WHERE token=?" "$token")"
    if [ "$CUR_OUTCOME" = "$outcome" ]; then
      CUR_USED="$(teamdb_exec_value "$DB" "SELECT attempts_used FROM attempts WHERE token=?" "$token")"
      CUR_MAX="$(teamdb_exec_value "$DB" "SELECT max_attempts FROM attempts WHERE token=?" "$token")"
      echo "state=complete token=$token outcome=$outcome attempts=${CUR_USED:-0}/${CUR_MAX:-3} (replay idempotente, no se incrementó)"
      exit 0
    fi
    echo "ERROR: token ya está complete con outcome '$CUR_OUTCOME' (recibido '$outcome'); contradicción de estados, no se incrementó" >&2
    exit 1
  fi

  # Incremento condicional: abandoned NO consume intento.
  local inc=0
  [ "$outcome" != "abandoned" ] && inc=1
  if ! OUT="$(teamdb_exec_write "$DB" \
    "UPDATE attempts SET state='complete', outcome=?, evidence=?, attempts_used = attempts_used + ?, updated_at=datetime('now') WHERE token=? AND state='proceed'" \
    "$outcome" "$evidence" "$inc" "$token" 2>&1)"; then
    echo "ERROR: no se pudo actualizar el intento ($OUT)" >&2
    exit 1
  fi
  # Verificar changes(): 0 → otro proceso settleó primero (race) → sin incrementar.
  CHANGES="$(printf '%s' "$OUT" | python3 -c "
import json, sys
try:
    print(json.load(sys.stdin).get('changes', 0))
except Exception:
    print(0)
")"
  if [ "${CHANGES:-0}" = "0" ]; then
    CUR_OUTCOME2="$(teamdb_exec_value "$DB" "SELECT outcome FROM attempts WHERE token=?" "$token")"
    if [ "$CUR_OUTCOME2" = "$outcome" ]; then
      CUR_USED2="$(teamdb_exec_value "$DB" "SELECT attempts_used FROM attempts WHERE token=?" "$token")"
      CUR_MAX2="$(teamdb_exec_value "$DB" "SELECT max_attempts FROM attempts WHERE token=?" "$token")"
      echo "state=complete token=$token outcome=$outcome attempts=${CUR_USED2:-0}/${CUR_MAX2:-3} (otro proceso settleó primero con el mismo outcome, no se incrementó)"
      exit 0
    fi
    echo "ERROR: token ya complete con outcome '$CUR_OUTCOME2' (recibido '$outcome'); contradicción de estados" >&2
    exit 1
  fi

  # La puerta es POR CHANGE, no por token: suma los intentos usados de TODOS
  # los intentos del change contra el tope del intento más reciente.
  CHANGE_A="$(teamdb_exec_value "$DB" "SELECT change_name FROM attempts WHERE token=?" "$token")"
  USED_A="$(teamdb_exec_value "$DB" "SELECT COALESCE(SUM(attempts_used), 0) FROM attempts WHERE change_name=?" "$CHANGE_A")"
  MAX_A="$(teamdb_exec_value "$DB" "SELECT max_attempts FROM attempts WHERE change_name=? ORDER BY id DESC LIMIT 1" "$CHANGE_A")"
  [ -n "$MAX_A" ] || MAX_A="3"
  if [ "$outcome" = "ok" ]; then
    RESULT="complete"
  elif [ "${USED_A:-0}" -ge "$MAX_A" ]; then
    RESULT="blocked"
  else
    RESULT="proceed"
  fi
  # FASE 1: dump fresco post-escritura (solo si el settle mutó la DB)
  teamdb_refresh_dump "$PROJECT" >/dev/null 2>&1 || true
  echo "state=$RESULT token=$token outcome=$outcome attempts=$USED_A/$MAX_A"
  exit 0
}

cmd_status() {
  local change=""
  while [ "$#" -gt 0 ]; do
    case "$1" in
      --change) change="${2:-}"; shift 2 ;;
      --help|-h) usage; exit 0 ;;
      *) PROJECT="$1"; shift ;;
    esac
  done
  setup_db
  printf 'id\ttoken\tchange\tstate\toutcome\tattempts/max\trequest_id\tcreated_at\n'
  if [ -n "$change" ]; then
    # Escapado SQL para el filtro (mismo _sql_quote que lib-teamdb.sh).
    sqlite3 -separator $'\t' "$DB" "SELECT id, token, change_name, state, COALESCE(outcome,'-'), attempts_used || '/' || max_attempts, request_id, created_at FROM attempts WHERE change_name = $(_sql_quote "$change") ORDER BY id DESC"
  else
    sqlite3 -separator $'\t' "$DB" "SELECT id, token, change_name, state, COALESCE(outcome,'-'), attempts_used || '/' || max_attempts, request_id, created_at FROM attempts ORDER BY id DESC"
  fi
  exit 0
}

CMD="${1:-}"
shift 2>/dev/null || true
PROJECT="$(pwd)"

case "$CMD" in
  acquire) cmd_acquire "$@" ;;
  settle) cmd_settle "$@" ;;
  status) cmd_status "$@" ;;
  --help|-h|"") usage; exit 0 ;;
  *)
    echo "ERROR: comando desconocido: $CMD" >&2
    usage >&2
    exit 2
    ;;
esac
