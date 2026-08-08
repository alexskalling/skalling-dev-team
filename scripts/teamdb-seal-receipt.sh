#!/usr/bin/env bash
# teamdb-seal-receipt.sh — Emite un receipt SELLADO con tree_hash (revisión congelada)
# v0.8.3: congela el hash del árbol que se revisó para que pre-commit verifique
# que los archivos staged son EXACTAMENTE los que se revisaron.
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

# TREE_HASH: hash del contenido que se va a commitear.
# - Con cambios staged/unstaged: git diff HEAD (NO write-tree, incluye archivos no staged).
# - Sin cambios respecto a HEAD (árbol limpio): NO se sella — fail-closed (bug D).
# - Repo sin commits: hash de lo staged (diff --cached); sin staged, tampoco.
# FASE 0: el dump versionado (db/teamdb/team.dump.sql) se EXCLUYE del hash —
# es un artefacto derivado de la DB, no código revisado. El pre-commit usa el
# mismo pathspec, así el seal y el gate siempre coinciden aunque la DB cambie.
TREE_HASH="${TEAMDB_CLAIM_TREE_HASH:-}"
DUMP_EXCLUDE=':(exclude)db/teamdb/team.dump.sql'
if [ -z "$TREE_HASH" ]; then
  HEAD_SHA="$(git -C "$PROJECT" rev-parse --verify HEAD 2>/dev/null || echo "")"
  if [ -n "$HEAD_SHA" ]; then
    DIFF_TEXT="$(git -C "$PROJECT" diff HEAD -- . "$DUMP_EXCLUDE" 2>/dev/null || true)"
    if [ -n "$DIFF_TEXT" ]; then
      TREE_HASH="$(printf '%s' "$DIFF_TEXT" | shasum -a 256 | cut -c1-16)"
    else
      # v0.8.3 (bug D): NO sellar un árbol limpio con el hash de HEAD. El
      # pre-push compara el hash del DIFF del rango (base..local), que jamás
      # matchea un sha de HEAD → push bloqueado con error confuso. Fail-closed:
      # sin diff no hay nada que sellar → error claro. Orden correcto:
      # 1) cambios staged (git add), 2) sellar, 3) commitear, 4) pushear.
      echo "ERROR: nada que sellar — el árbol de trabajo está limpio (sin diff respecto a HEAD)." >&2
      echo "       Sellar y commitear siguen el orden: staged (git add) → sellar → commitear." >&2
      echo "       Si ya commiteaste, revertí o hacé amend y re-sellá antes de commitear de nuevo." >&2
      exit 1
    fi
  else
    DIFF_TEXT="$(git -C "$PROJECT" diff --cached -- . "$DUMP_EXCLUDE" 2>/dev/null || true)"
    if [ -n "$DIFF_TEXT" ]; then
      TREE_HASH="$(printf '%s' "$DIFF_TEXT" | shasum -a 256 | cut -c1-16)"
    else
      # Repo sin commits y sin nada staged: nada que sellar tampoco.
      echo "ERROR: nada que sellar — no hay cambios staged ni commits." >&2
      echo "       Modificá el código y stagealo antes de sellar." >&2
      exit 1
    fi
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

exit 0
