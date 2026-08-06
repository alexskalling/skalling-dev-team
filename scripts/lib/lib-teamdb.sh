#!/usr/bin/env bash
# lib-teamdb.sh — Wrapper bash para libSQL

teamdb_global_path() {
  echo "${HOME}/.config/opencode/team.db"
}

teamdb_project_path() {
  local project="${1:-$(pwd)}"
  echo "${project}/.opencode/context/team.db"
}

teamdb_check_sqlite3() {
  if ! command -v sqlite3 >/dev/null 2>&1; then
    echo "[ERROR] sqlite3 no instalado" >&2
    return 1
  fi
}

teamdb_query_global() {
  teamdb_check_sqlite3 || return 1
  sqlite3 -separator $'\t' "$(teamdb_global_path)" "$1"
}

teamdb_query_project() {
  teamdb_check_sqlite3 || return 1
  local db; db="$(teamdb_project_path "${2:-$(pwd)}")"
  [ -f "$db" ] || { echo "[ERROR] DB no existe: $db" >&2; return 1; }
  sqlite3 -separator $'\t' "$db" "$1"
}

# teamdb_write_project: usa teamdb_exec.py multi-statement atómico (T-2.11).
# Reemplaza el flock anterior. SQLite con WAL maneja concurrencia via journal_mode.
# DEV-2.11: path activo para writes seguros; teamdb_safe_query queda deprecada.
teamdb_write_project() {
  local db="$1"; local sql="$2"; shift 2
  [ -f "$db" ] || { echo "[ERROR] DB no existe: $db" >&2; return 1; }
  local actor="${TEAMDB_ACTOR:-unknown}"
  local user_params_json
  user_params_json="$(python3 -c "import json,sys; print(json.dumps(list(sys.argv[1:])))" "$@")"
  # batches: [audit_row con actor/table_marker, user SQL con user_params]
  local batches_json
  batches_json="$(python3 -c "import json,sys
print(json.dumps([
  {'sql':'INSERT INTO audit_log(ts,agent,action,table_name,actor_source) VALUES(datetime(\"now\"),?,\"mutate\",?,?)', 'params':[sys.argv[1], sys.argv[2], 'helper']},
  {'sql':sys.argv[3], 'params':json.loads(sys.argv[4])}
]))" "$actor" "<via_helper>" "$sql" "$user_params_json")"
  teamdb_exec_multi "$db" "$batches_json"
}

# teamdb_write_global: simétrico para ~/.config/opencode/team.db
teamdb_write_global() {
  local sql="$1"; shift
  local db; db="$(teamdb_global_path)"
  [ -f "$db" ] || { echo "[ERROR] DB global no existe: $db" >&2; return 1; }
  local actor="${TEAMDB_ACTOR:-unknown}"
  local user_params_json
  user_params_json="$(python3 -c "import json,sys; print(json.dumps(list(sys.argv[1:])))" "$@")"
  local batches_json
  batches_json="$(python3 -c "import json,sys
print(json.dumps([
  {'sql':'INSERT INTO audit_log(ts,agent,action,table_name,actor_source) VALUES(datetime(\"now\"),?,\"mutate-global\",?,?)', 'params':[sys.argv[1], sys.argv[2], 'helper']},
  {'sql':sys.argv[3], 'params':json.loads(sys.argv[4])}
]))" "$actor" "<via_helper-global>" "$sql" "$user_params_json")"
  teamdb_exec_multi "$db" "$batches_json"
}

teamdb_with_lock() {
  local lock_path="$1"
  shift
  mkdir -p "$(dirname "$lock_path")"
  if command -v flock >/dev/null 2>&1; then
    (
      flock -w 5 200 || { echo "[ERROR] No lock $lock_path" >&2; return 1; }
      "$@"
    ) 200>"$lock_path.lock" >/dev/null 2>&1
  else
    "$@"
  fi
}

teamdb_init_project() {
  teamdb_check_sqlite3 || return 1
  export TEAMDB_ACTOR="${TEAMDB_ACTOR:-sol}"
  local project="${1:-$(pwd)}"
  local db; db="$(teamdb_project_path "$project")"
  local schema="${SKALLING_ROOT:-$(dirname "$(dirname "${BASH_SOURCE[0]}")")}/sql/project-schema.sql"
  [ -f "$schema" ] || { echo "[ERROR] Schema: $schema" >&2; return 1; }
  mkdir -p "$(dirname "$db")"
  if [ ! -f "$db" ]; then
    sqlite3 "$db" < "$schema"
    # T-2.11: setear PRAGMAs en DBs nuevas (idempotente)
    sqlite3 "$db" "PRAGMA journal_mode=WAL; PRAGMA busy_timeout=5000; PRAGMA foreign_keys=ON" 2>/dev/null || true
  fi
  echo "$db"
}

# teamdb_heal_global: upgrade aditivo idempotente del team.db global (DBs viejas).
# 1) crea audit_log si la DB es pre-0.7.2; 2) añade actor_source si falta la
# columna; 3) v0.7.3: skills_active como indice (description/load_path); 4) deja
# schema_meta.version al día (si existe la tabla).
# En DBs nuevas (recién creadas del schema actual) es un no-op.
# NOTA: al bumpear versión, actualizar el valor '0.7.6' de abajo.
teamdb_heal_global() {
  teamdb_check_sqlite3 || return 1
  local db; db="$(teamdb_global_path)"
  [ -f "$db" ] || { echo "[ERROR] DB global no existe: $db" >&2; return 1; }
  sqlite3 "$db" <<'SQL' || { echo "[ERROR] Heal teamdb global falló: $db" >&2; return 1; }
CREATE TABLE IF NOT EXISTS audit_log (
  id INTEGER PRIMARY KEY,
  ts TEXT NOT NULL,
  agent TEXT,
  action TEXT,
  table_name TEXT,
  row_id INTEGER,
  details TEXT,
  actor_source TEXT DEFAULT 'trigger'
);
CREATE INDEX IF NOT EXISTS idx_audit_ts ON audit_log(ts DESC);
SQL
  local has_col
  has_col="$(sqlite3 "$db" "SELECT 1 FROM pragma_table_info('audit_log') WHERE name='actor_source'" 2>/dev/null)"
  if [ "$has_col" != "1" ]; then
    sqlite3 "$db" "ALTER TABLE audit_log ADD COLUMN actor_source TEXT DEFAULT 'trigger'" || {
      echo "[ERROR] No se pudo añadir actor_source al team.db global" >&2
      return 1
    }
  fi
  # v0.7.3: skills_active como indice (description/load_path). Si la tabla no
  # existe (DB pre-v0.7.2), crearla completa. Idempotente.
  sqlite3 "$db" <<'SQL'
CREATE TABLE IF NOT EXISTS skills_active (
  id INTEGER PRIMARY KEY,
  skill_name TEXT NOT NULL UNIQUE,
  source TEXT,
  installed_at TEXT,
  version TEXT,
  description TEXT,
  load_path TEXT
);
SQL
  for col in "description TEXT" "load_path TEXT"; do
    local colname="${col%% *}"
    if [ "$(sqlite3 "$db" "SELECT 1 FROM pragma_table_info('skills_active') WHERE name='$colname'" 2>/dev/null)" != "1" ]; then
      sqlite3 "$db" "ALTER TABLE skills_active ADD COLUMN $col" 2>/dev/null || true
    fi
  done
  sqlite3 "$db" "UPDATE schema_meta SET value='0.7.6' WHERE key='version'" 2>/dev/null || true
  return 0
}

teamdb_init_global() {
  teamdb_check_sqlite3 || return 1
  local db; db="$(teamdb_global_path)"
  local schema="${SKALLING_ROOT:-$(dirname "$(dirname "${BASH_SOURCE[0]}")")}/sql/global-schema.sql"
  [ -f "$schema" ] || { echo "[ERROR] Schema: $schema" >&2; return 1; }
  mkdir -p "$(dirname "$db")"
  if [ ! -f "$db" ]; then
    sqlite3 "$db" < "$schema" || { echo "[ERROR] No se pudo crear DB global: $db" >&2; return 1; }
  fi
  teamdb_heal_global || return 1
  echo "$db"
}

# teamdb_exec.py: wrapper Python con real parameter binding (T-2.10).
# CAMINO ACTIVO para SQL seguro. teamdb_safe_query queda DEPRECATED.
_TEAMDB_EXEC_PY=""
_resolve_teamdb_exec_py() {
  [ -n "$_TEAMDB_EXEC_PY" ] && return 0
  local lib_dir
  lib_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
  if [ -f "$lib_dir/../teamdb_exec.py" ]; then
    _TEAMDB_EXEC_PY="$lib_dir/../teamdb_exec.py"
  elif [ -f "$lib_dir/teamdb_exec.py" ]; then
    _TEAMDB_EXEC_PY="$lib_dir/teamdb_exec.py"
  fi
}

teamdb_exec_query() {
  _resolve_teamdb_exec_py || { echo "[ERROR] teamdb_exec.py no encontrado" >&2; return 1; }
  command -v python3 >/dev/null 2>&1 || { echo "[ERROR] python3 requerido" >&2; return 1; }
  local db="$1"; local sql="$2"; shift 2
  local params_json
  params_json="$(python3 -c "import json,sys; print(json.dumps(list(sys.argv[1:])))" "$@")"
  python3 "$_TEAMDB_EXEC_PY" --db "$db" --mode query --sql "$sql" --params "$params_json"
}

# teamdb_exec_value: retorna el primer valor escalar (string) de la primera fila.
# Si 0 filas, retorna vacio. Si N filas, retorna la primera.
teamdb_exec_value() {
  _resolve_teamdb_exec_py || { echo "[ERROR] teamdb_exec.py no encontrado" >&2; return 1; }
  command -v python3 >/dev/null 2>&1 || { echo "[ERROR] python3 requerido" >&2; return 1; }
  local db="$1"; local sql="$2"; shift 2
  local params_json
  params_json="$(python3 -c "import json,sys; print(json.dumps(list(sys.argv[1:])))" "$@")"
  python3 "$_TEAMDB_EXEC_PY" --db "$db" --mode query --sql "$sql" --params "$params_json" | \
    python3 -c "
import json, sys
try:
    rows = json.loads(sys.stdin.read())
    if not rows: sys.exit(0)
    row = rows[0]
    if not row: sys.exit(0)
    # Si la primera fila tiene una sola key, retorna el valor
    if len(row) == 1:
        v = list(row.values())[0]
        print('' if v is None else v)
    else:
        # Multi-columna: print como tab-separated
        print('\t'.join('' if v is None else str(v) for v in row.values()))
except Exception:
    sys.exit(0)
"
}

teamdb_exec_write() {
  _resolve_teamdb_exec_py || { echo "[ERROR] teamdb_exec.py no encontrado" >&2; return 1; }
  command -v python3 >/dev/null 2>&1 || { echo "[ERROR] python3 requerido" >&2; return 1; }
  local db="$1"; local sql="$2"; shift 2
  local params_json
  params_json="$(python3 -c "import json,sys; print(json.dumps(list(sys.argv[1:])))" "$@")"
  python3 "$_TEAMDB_EXEC_PY" --db "$db" --mode write --sql "$sql" --params "$params_json"
}

teamdb_exec_transaction() {
  _resolve_teamdb_exec_py || { echo "[ERROR] teamdb_exec.py no encontrado" >&2; return 1; }
  command -v python3 >/dev/null 2>&1 || { echo "[ERROR] python3 requerido" >&2; return 1; }
  local db="$1"; local sql="$2"; shift 2
  local params_json
  params_json="$(python3 -c "import json,sys; print(json.dumps(list(sys.argv[1:])))" "$@")"
  python3 "$_TEAMDB_EXEC_PY" --db "$db" --mode transaction --sql "$sql" --params "$params_json"
}

# teamdb_exec_multi <db> <batches_json>
# Ejecuta multiples (sql, params) atómicamente en BEGIN IMMEDIATE.
# batches_json = '[{"sql":"...","params":[...]}, ...]'
teamdb_exec_multi() {
  _resolve_teamdb_exec_py || { echo "[ERROR] teamdb_exec.py no encontrado" >&2; return 1; }
  command -v python3 >/dev/null 2>&1 || { echo "[ERROR] python3 requerido" >&2; return 1; }
  local db="$1"; local batches_json="$2"
  python3 "$_TEAMDB_EXEC_PY" --db "$db" --mode multi --sql "" --params-batches "$batches_json"
}

# teamdb_safe_query: wrapper con validacion + escape seguro.
# Uso:
#   teamdb_safe_query "$DB" <mode> <template_sql> <param>...
# Modes: fts | like | exact
# - Rechaza NUL/control chars en parametros
# - Rechaza parametros > 1024 chars
# - Valida DB y mode
# - DESVIACION del plan T-1.1: el CLI sqlite3 NO soporta bind de ?/?N/:name.
#   Se hace escape explicito ' -> '' (estandar SQL) y se sustituye ? en template.
#   Es seguro porque: (1) el caller pasa templates con ? solo en valores,
#   (2) nombres de tabla/column vienen del caller como literales en el template
#   (e.g., "SELECT id FROM $TABLE WHERE slug = ?") y $TABLE es un whitelist.
teamdb_safe_query() {
  teamdb_check_sqlite3 || return 1
  local db="$1"
  local mode="$2"
  local template="$3"
  shift 3 || { echo "[ERROR] teamdb_safe_query: args insuficientes" >&2; return 1; }

  [ -f "$db" ] || { echo "[ERROR] DB no existe: $db" >&2; return 1; }

  case "$mode" in
    fts|like|exact) ;;
    *) echo "[ERROR] Mode invalido: $mode (usa fts|like|exact)" >&2; return 1 ;;
  esac

  local arg
  for arg in "$@"; do
    _validate_param "$arg" || return 1
  done

  local sql="$template"
  for arg in "$@"; do
    case "$mode" in
      exact|fts)
        sql="${sql/\?/$(_sql_quote "$arg")}"
        ;;
      like)
        sql="${sql/\?/$(_sql_quote_like "$arg")}"
        ;;
    esac
  done

  sqlite3 -separator $'\t' "$db" "$sql"
}

_teamdb_max_param_len=1024

_validate_param() {
  local arg="$1"
  if [ -z "$arg" ]; then
    return 0
  fi
  if _has_control_char "$arg"; then
    echo "[ERROR] Invalid input (control chars)" >&2
    return 1
  fi
  if [ "${#arg}" -gt "$_teamdb_max_param_len" ]; then
    echo "[ERROR] Too long (max $_teamdb_max_param_len chars)" >&2
    return 1
  fi
  return 0
}

# _sql_quote: envuelve en '...' con escape de comillas (estandar SQL).
_sql_quote() {
  printf "'%s'" "$(printf '%s' "$1" | sed "s/'/''/g")"
}

# _sql_quote_like: igual + escapa wildcards % y _ para uso en LIKE.
_sql_quote_like() {
  printf "'%s'" "$(printf '%s' "$1" | sed -e "s/'/''/g" -e "s/%/\\%/g" -e "s/_/\\_/g")"
}

# teamdb_has_table: retorna 1 si la tabla existe, 0 si no. Sin interpolacion user-input.
teamdb_has_table() {
  teamdb_check_sqlite3 || return 1
  local db="$1"
  local table="$2"
  [ -f "$db" ] || return 1
  case "$table" in
    *[!a-zA-Z0-9_]*) return 1 ;;
  esac
  local row
  row="$(sqlite3 -separator $'\t' "$db" "SELECT 1 FROM sqlite_master WHERE type='table' AND name='$table' LIMIT 1" 2>/dev/null || true)"
  [ -n "$row" ] && return 0
  return 1
}

# _actor_or_unknown: retorna TEAMDB_ACTOR si está exportado, sino 'unknown'.
# INV-AUDIT-1: el actor en audit_log debe reflejar el agente que invoca,
# no un literal. Esta función es la fundación — la integración completa
# con teamdb_write_* se hace en T-2.2 (escritura helper-side).
_actor_or_unknown() {
  echo "${TEAMDB_ACTOR:-unknown}"
}

# _has_control_char: portable bash 3.2, sin grep -P / LC_ALL=C / od.
# Itera cada byte y compara contra control chars problematicos.
# Acepta TAB (0x09), LF (0x0A), CR (0x0D) por ser razonables.
_has_control_char() {
  local s="$1"
  local len="${#s}"
  local i=0
  while [ "$i" -lt "$len" ]; do
    case "${s:$i:1}" in
      $'\x00'|$'\x01'|$'\x02'|$'\x03'|$'\x04'|$'\x05'|$'\x06'|$'\x07'|$'\x08'|$'\x0b'|$'\x0c'|$'\x0e'|$'\x0f'|$'\x10'|$'\x11'|$'\x12'|$'\x13'|$'\x14'|$'\x15'|$'\x16'|$'\x17'|$'\x18'|$'\x19'|$'\x1a'|$'\x1b'|$'\x1c'|$'\x1d'|$'\x1e'|$'\x1f'|$'\x7f')
        return 0
        ;;
    esac
    i=$((i + 1))
  done
  return 1
}
