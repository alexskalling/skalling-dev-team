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

teamdb_with_lock() {
  local lock_path="$1"
  shift
  mkdir -p "$(dirname "$lock_path")"
  if command -v flock >/dev/null 2>&1; then
    (
      flock -w 5 200 || { echo "[ERROR] No lock $lock_path" >&2; return 1; }
      "$@"
    ) 200>"$lock_path.lock"
  else
    "$@"
  fi
}

teamdb_init_project() {
  teamdb_check_sqlite3 || return 1
  local project="${1:-$(pwd)}"
  local db; db="$(teamdb_project_path "$project")"
  local schema="${SKALLING_ROOT:-$(dirname "$(dirname "${BASH_SOURCE[0]}")")}/sql/project-schema.sql"
  [ -f "$schema" ] || { echo "[ERROR] Schema: $schema" >&2; return 1; }
  mkdir -p "$(dirname "$db")"
  [ -f "$db" ] || sqlite3 "$db" < "$schema"
  echo "$db"
}

teamdb_init_global() {
  teamdb_check_sqlite3 || return 1
  local db; db="$(teamdb_global_path)"
  local schema="${SKALLING_ROOT:-$(dirname "$(dirname "${BASH_SOURCE[0]}")")}/sql/global-schema.sql"
  [ -f "$schema" ] || { echo "[ERROR] Schema: $schema" >&2; return 1; }
  mkdir -p "$(dirname "$db")"
  [ -f "$db" ] || sqlite3 "$db" < "$schema"
  echo "$db"
}
