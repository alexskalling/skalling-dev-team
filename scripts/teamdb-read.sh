#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT="${PROJECT:-$(pwd)}"

if [ "${1:-}" = "--project" ]; then
  PROJECT="${2:?Falta project}"
  shift 2
fi

SQL="${1:-}"
[ -n "$SQL" ] || {
  echo "Uso: teamdb-read.sh [--project <path>] <SELECT> [params...]" >&2
  exit 2
}
shift

case "$(printf '%s' "$SQL" | sed -E 's/^[[:space:]]*//;s/^([[:alpha:]]+).*/\1/' | tr '[:upper:]' '[:lower:]')" in
  select|explain) ;;
  *) echo "ERROR: teamdb-read.sh solo acepta SELECT o EXPLAIN" >&2; exit 2 ;;
esac

DB="$PROJECT/.opencode/context/team.db"
[ -f "$DB" ] || { echo "ERROR: DB no existe: $DB" >&2; exit 1; }

PARAMS="$(python3 -c 'import json,sys; print(json.dumps(sys.argv[1:]))' "$@")"
python3 "$SCRIPT_DIR/teamdb_exec.py" --db "$DB" --mode query --sql "$SQL" --params "$PARAMS"
echo
