#!/usr/bin/env bash
# lib-teamdb.sh — Wrapper bash para libSQL

teamdb_global_path() {
  echo "${SKALLING_DB_GLOBAL:-${SKALLING_OPENCODE_DIR:-${HOME}/.config/opencode}/team.db}"
}

# _teamdb_project_root <dir>: si <dir> es un git worktree LINKED (no el
# principal), resuelve a la raiz del repo principal. team.db esta gitignored
# y solo existe ahi -- un worktree nuevo nunca lo trae consigo, asi que
# resolver la ruta de la DB contra la raiz del worktree hace que CUALQUIER
# operacion de TeamDB (claim, plan, seal-receipt, etc.) "no encuentre" una
# base que en realidad existe, uno o dos directorios al lado. Encontrado por
# una revision independiente al escribir el fix fail-closed de git-gate.py,
# que tenia el mismo bug antes de esto.
_teamdb_project_root() {
  local project="$1"
  if [ -d "$project/.git" ] || [ -f "$project/.git" ]; then
    local common_dir
    common_dir="$(cd "$project" 2>/dev/null && git rev-parse --git-common-dir 2>/dev/null)" || { echo "$project"; return; }
    case "$common_dir" in
      /*) : ;;
      *) common_dir="$project/$common_dir" ;;
    esac
    (cd "$common_dir/.." 2>/dev/null && pwd) || echo "$project"
  else
    echo "$project"
  fi
}

teamdb_project_path() {
  local project="${1:-$(pwd)}"
  echo "$(_teamdb_project_root "$project")/.opencode/context/team.db"
}

# Resuelve quién ejecuta una acción que queda registrada (aprobar, liberar,
# sellar). Si el plugin de OpenCode fijó SKALLING_RUNTIME_AGENT, esa es la
# identidad real y manda: un --by/--actor distinto es una falsificación (ej.
# Teo intentando aprobar como jhon) y se rechaza. Sin runtime (CLI humano,
# tests), vale lo declarado.
# Uso: actor="$(teamdb_runtime_actor "$declarado")" || exit 2
teamdb_runtime_actor() {
  local declared runtime
  declared="$(printf '%s' "${1:-}" | tr '[:upper:]' '[:lower:]')"
  runtime="$(printf '%s' "${SKALLING_RUNTIME_AGENT:-}" | tr '[:upper:]' '[:lower:]')"
  if [ -z "$runtime" ]; then
    printf '%s\n' "${1:-unknown}"
    return 0
  fi
  if [ -n "$declared" ] && [ "$declared" != "unknown" ] && [ "$declared" != "$runtime" ]; then
    echo "ERROR: identidad declarada '$1' no coincide con el agente real '$runtime' (la pone OpenCode)" >&2
    return 1
  fi
  printf '%s\n' "$runtime"
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
# DEV-2.11: path activo para writes seguros.
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
# NOTA: al bumpear versión, actualizar el valor '0.8.3' de abajo.
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
CREATE TABLE IF NOT EXISTS routing_decisions (
  id INTEGER PRIMARY KEY,
  ts TEXT NOT NULL,
  user_intent TEXT NOT NULL,
  chosen_route TEXT NOT NULL CHECK (chosen_route IN ('DISCOVERY','INLINE','INTERVENTION','FAST-TRACK','SDD','DIRECT','RESEARCH')),
  route_reason TEXT,
  agents_involved TEXT,
  outcome TEXT DEFAULT 'PENDING' CHECK (outcome IN ('PENDING','SUCCESS','FAIL','CANCELLED')),
  completed_at TEXT
);
CREATE INDEX IF NOT EXISTS idx_routing_decisions_ts ON routing_decisions(ts);
CREATE TABLE IF NOT EXISTS workflow_state (
  id INTEGER PRIMARY KEY CHECK (id = 1),
  active_cycle_slug TEXT,
  phase TEXT,
  actor TEXT,
  started_at TEXT,
  lock_token TEXT,
  updated_at TEXT
);
CREATE TABLE IF NOT EXISTS workflow_metrics (
  request_id TEXT PRIMARY KEY,
  risk_level TEXT NOT NULL CHECK (risk_level IN ('low','medium','high')),
  route TEXT,
  agents_count INTEGER DEFAULT 0,
  handoffs INTEGER DEFAULT 0,
  permission_prompts INTEGER DEFAULT 0,
  context_bytes INTEGER DEFAULT 0,
  started_at TEXT NOT NULL,
  completed_at TEXT,
  duration_ms INTEGER,
  outcome TEXT
);
CREATE INDEX IF NOT EXISTS idx_workflow_metrics_started ON workflow_metrics(started_at DESC);
SQL
  # CREATE TABLE IF NOT EXISTS de arriba es un no-op sobre una tabla que ya
  # existe, aunque su CHECK constraint sea el viejo -- SQLite no permite
  # ALTER de un CHECK. Una DB global creada antes de que 'DISCOVERY' se
  # agregara al contrato de routing quedaba con el constraint viejo para
  # siempre pese a reinstalar. Mismo rebuild que ya usa la migracion
  # 024_version_0_10_3.sql para las DBs de proyecto; aca aplicado al global.
  local routing_needs_discovery
  routing_needs_discovery="$(sqlite3 "$db" "SELECT CASE WHEN sql NOT LIKE '%DISCOVERY%' THEN 1 ELSE 0 END FROM sqlite_master WHERE type='table' AND name='routing_decisions'" 2>/dev/null || echo 0)"
  if [ "$routing_needs_discovery" = "1" ]; then
    sqlite3 "$db" <<'SQL' || { echo "[ERROR] No se pudo migrar routing_decisions (agregar DISCOVERY) en team.db global" >&2; return 1; }
PRAGMA foreign_keys=OFF;
BEGIN TRANSACTION;
CREATE TABLE routing_decisions_new (
  id INTEGER PRIMARY KEY,
  ts TEXT NOT NULL,
  user_intent TEXT NOT NULL,
  chosen_route TEXT NOT NULL CHECK (chosen_route IN ('DISCOVERY','INLINE','INTERVENTION','FAST-TRACK','SDD','DIRECT','RESEARCH')),
  route_reason TEXT,
  agents_involved TEXT,
  outcome TEXT DEFAULT 'PENDING' CHECK (outcome IN ('PENDING','SUCCESS','FAIL','CANCELLED')),
  completed_at TEXT
);
INSERT INTO routing_decisions_new
  (id, ts, user_intent, chosen_route, route_reason, agents_involved, outcome, completed_at)
SELECT id, ts, user_intent, chosen_route, route_reason, agents_involved, outcome, completed_at
FROM routing_decisions;
DROP TABLE routing_decisions;
ALTER TABLE routing_decisions_new RENAME TO routing_decisions;
CREATE INDEX IF NOT EXISTS idx_routing_decisions_ts ON routing_decisions(ts);
CREATE INDEX IF NOT EXISTS idx_routing_decisions_route ON routing_decisions(chosen_route);
COMMIT;
PRAGMA foreign_keys=ON;
SQL
  fi
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
  # Validar que las correcciones aditivas quedaron aplicadas antes de bumpear
  # la versión. Sin esto, una DB con schema incompleto reportaba 0.8.3 mintiendo.
  local has_audit has_actor has_skills has_schema_meta has_routing has_metrics has_workflow
  has_audit="$(sqlite3 "$db" "SELECT count(*) FROM sqlite_master WHERE type='table' AND name='audit_log'" 2>/dev/null || true)"
  has_actor="$(sqlite3 "$db" "SELECT count(*) FROM pragma_table_info('audit_log') WHERE name='actor_source'" 2>/dev/null || true)"
  has_skills="$(sqlite3 "$db" "SELECT count(*) FROM sqlite_master WHERE type='table' AND name='skills_active'" 2>/dev/null || true)"
  has_schema_meta="$(sqlite3 "$db" "SELECT count(*) FROM sqlite_master WHERE type='table' AND name='schema_meta'" 2>/dev/null || true)"
  has_routing="$(sqlite3 "$db" "SELECT count(*) FROM sqlite_master WHERE type='table' AND name='routing_decisions'" 2>/dev/null || true)"
  has_metrics="$(sqlite3 "$db" "SELECT count(*) FROM sqlite_master WHERE type='table' AND name='workflow_metrics'" 2>/dev/null || true)"
  has_workflow="$(sqlite3 "$db" "SELECT count(*) FROM sqlite_master WHERE type='table' AND name='workflow_state'" 2>/dev/null || true)"
  if [ "${has_audit:-0}" = "0" ] || [ "${has_actor:-0}" = "0" ] || [ "${has_skills:-0}" = "0" ] || [ "${has_schema_meta:-0}" = "0" ] || [ "${has_routing:-0}" = "0" ] || [ "${has_metrics:-0}" = "0" ] || [ "${has_workflow:-0}" = "0" ]; then
    echo "[ERROR] teamdb heal: schema operativo incompleto; no se actualizó la versión" >&2
    return 1
  fi
  local target_version version_file
  version_file="${SKALLING_ROOT:-$(dirname "$(dirname "${BASH_SOURCE[0]}")")}/VERSION"
  target_version="$(grep '__version__' "$version_file" 2>/dev/null | sed 's/.*"\([^"]*\)".*/\1/' || true)"
  [ -n "$target_version" ] || { echo "[ERROR] No se pudo resolver VERSION" >&2; return 1; }
  if ! sqlite3 "$db" "UPDATE schema_meta SET value='$target_version' WHERE key='version'" 2>/dev/null; then
    echo "[ERROR] No se pudo actualizar schema_meta.version en $db" >&2
    return 1
  fi
  sqlite3 "$db" "INSERT INTO schema_meta(key,value) VALUES('legacy_surface.work_in_progress','read_only_compatibility') ON CONFLICT(key) DO UPDATE SET value=excluded.value" || return 1
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
# CAMINO ACTIVO para SQL seguro (bound params reales).
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

# _sql_quote: envuelve en '...' con escape de comillas (estandar SQL).
_sql_quote() {
  printf "'%s'" "$(printf '%s' "$1" | sed "s/'/''/g")"
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

# teamdb_lock / teamdb_unlock: lock cross-platform basado en mkdir (v0.8.3).
# Compatible con macOS (sin flock nativo), Linux y BSD. Sin dependencias externas.
# Usa atomicidad de mkdir(2): o crea el directorio o falla si ya existe.
# RECUPERACIÓN DE LOCKS STALE (v0.8.3): si mkdir falla y el lock pertenece a un
# pid MUERTO (o no tiene pid), se limpia y se reintenta. Sin esto, un SIGKILL
# dejaba el lock para siempre → todos los teamdb-* fallaban tras 10s con
# recuperación solo manual. NUNCA se toca un lock con pid vivo (kill -0 ok).
# Race: dos procesos pueden ver el mismo lock stale y limpiarlo a la vez; la
# atomicidad de mkdir(2) decide quién queda con el lock — el que logra el mkdir
# tras la limpieza es el dueño legítimo (los rm/rmdir del perdedor son no-ops).
# Un lock sin archivo pid puede ser un dueño en plena adquisición (mkdir hecho,
# pid por escribir): se da UNA vuelta de cortesía antes de declararlo stale.
# Uso:
#   LOCK_DIR="$PROJECT/.opencode/context/.locks/team"
#   mkdir -p "$(dirname "$LOCK_DIR")" 2>/dev/null || true
#   teamdb_lock "$LOCK_DIR" 10 || exit 1
#   trap 'teamdb_unlock "$LOCK_DIR"' EXIT
teamdb_lock() {
  local lock_dir="$1"
  local max_wait="${2:-10}"
  local waited=0
  local lock_pid=""

  while ! mkdir "$lock_dir" 2>/dev/null; do
    # Timeout global: cubre dueño vivo, lock sin pid y limpieza que no pudo
    # completarse. El mensaje final dice cómo recuperar manualmente.
    if [ "$waited" -ge "$max_wait" ]; then
      echo "ERROR: no se pudo obtener lock en $lock_dir (esperado ${max_wait}s)." >&2
      echo "       Si el lock quedó stale (proceso muerto): rm -f $lock_dir/pid && rmdir $lock_dir" >&2
      return 1
    fi
    lock_pid=""
    if [ -f "$lock_dir/pid" ]; then
      read -r lock_pid < "$lock_dir/pid" || true
    fi
    if [ -n "$lock_pid" ] && kill -0 "$lock_pid" 2>/dev/null; then
      # Dueño vivo → esperar el tick completo (nunca limpiar un lock vivo).
      sleep 1
      waited=$((waited + 1))
      continue
    fi
    # Stale: pid muerto/inválido/ausente → limpiar y reintentar el mkdir.
    if [ ! -f "$lock_dir/pid" ]; then
      # Vuelta de cortesía: si el dueño recién hizo mkdir y aún no escribió el
      # pid, no robarle el lock; si sigue sin pid, es stale de verdad.
      sleep 1
      waited=$((waited + 1))
      if [ -f "$lock_dir/pid" ]; then
        continue
      fi
    fi
    rm -f "$lock_dir/pid" 2>/dev/null
    rmdir "$lock_dir" 2>/dev/null
  done

  echo $$ > "$lock_dir/pid"
  return 0
}

teamdb_unlock() {
  local lock_dir="$1"
  rm -f "$lock_dir/pid" 2>/dev/null
  rmdir "$lock_dir" 2>/dev/null
}

# ─────────────────────────────────────────────────────────────────────────────
# FASE 1 — Dump fresco post-escritura.
#
# teamdb_refresh_dump [<project>]
#   Regenera db/teamdb/team.dump.sql desde la DB del proyecto. Los scripts de
#   ESCRITURA (plan/claim/execute/amend/seal/...) la llaman al final, así la
#   fotografía en el working tree queda fresca ANTES del commit y el pre-commit
#   no tiene que rescatar un diff grande de golpe.
#
#   - No-op si la DB o el script de dump no existen (repo sin Fase 0).
#   - Silencioso en éxito (el dump lo escribe teamdb-dump.sh).
#   - En fallo imprime WARN y NO aborta: el pre-commit sigue siendo el gate
#     final y el commit fallará ahí si el dump no se puede fotografiar.
teamdb_refresh_dump() {
  local project="${1:-$(pwd)}"
  local db dump_script
  db="$(teamdb_project_path "$project")"
  [ -f "$db" ] || return 0
  dump_script="${TEAMDB_DUMP_SCRIPT:-}"
  if [ -z "$dump_script" ]; then
    for candidate in \
      "${SKALLING_ROOT:-}/scripts/teamdb-dump.sh" \
      "$(dirname "${BASH_SOURCE[0]}")/../teamdb-dump.sh" \
      "$project/scripts/teamdb-dump.sh"; do
      if [ -f "$candidate" ]; then
        dump_script="$candidate"
        break
      fi
    done
  fi
  [ -n "$dump_script" ] || return 0
  bash "$dump_script" "$project" >/dev/null 2>&1 || {
    echo "WARN: teamdb_refresh_dump no pudo regenerar el dump (verificá secretos en la DB)" >&2
    return 1
  }
  return 0
}
