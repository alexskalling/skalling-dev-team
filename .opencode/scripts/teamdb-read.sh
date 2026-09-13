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

# Todos los demas teamdb-*.sh toman el proyecto como ultimo argumento
# posicional; este exigia --project al PRINCIPIO, con cualquier extra al
# final tratado ciegamente como bind param. Confuso en uso real: pasar el
# proyecto al final (la convencion de todo el resto) producia
# "Incorrect number of bindings supplied" en vez de un error claro.
# Si sobra exactamente un argumento mas que placeholders '?' en el SQL Y
# ese argumento es un directorio existente, se interpreta como proyecto
# (no como bind param) -- una string de valor real casi nunca coincide
# con una ruta de directorio real, asi que la ambiguedad es minima.
if [ "$#" -gt 0 ]; then
  placeholder_count="$(printf '%s' "$SQL" | tr -cd '?' | wc -c | tr -d ' ')"
  last_arg="${!#}"
  if [ "$#" -eq $((placeholder_count + 1)) ] && [ -d "$last_arg" ]; then
    PROJECT="$last_arg"
    set -- "${@:1:$#-1}"
  fi
fi

DB="$PROJECT/.opencode/context/team.db"
[ -f "$DB" ] || { echo "ERROR: DB no existe: $DB" >&2; exit 1; }

PARAMS="$(python3 -c 'import json,sys; print(json.dumps(sys.argv[1:]))' "$@")"
python3 "$SCRIPT_DIR/teamdb_exec.py" --db "$DB" --mode query --sql "$SQL" --params "$PARAMS"
echo
