#!/usr/bin/env bash
# skalling-coverage.sh — corre el comando de cobertura del proyecto (detectado
# en project.yaml por bootstrap-context.sh) y guarda el resultado en TeamDB.
#
# Uso: skalling-coverage.sh [project]
#
# Nunca inventa un porcentaje: si el comando no esta configurado, no corre
# nada. Si corre pero el formato de salida no se reconoce, igual queda un
# registro en coverage_runs con percent NULL y una nota explicando por que.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT="${1:-$(pwd)}"
YAML="$PROJECT/.opencode/project.yaml"
DB="$PROJECT/.opencode/context/team.db"

[ -f "$YAML" ] || { echo "ERROR: no existe $YAML. Corré /skalling-init primero." >&2; exit 1; }
[ -f "$DB" ] || { echo "ERROR: TeamDB no existe: $DB" >&2; exit 1; }

COMMAND="$(python3 -c '
import re, sys
text = open(sys.argv[1], encoding="utf-8").read()
m = re.search(r"coverage:\s*\n\s*available:\s*\w+\s*\n\s*command:\s*(.*)", text)
print((m.group(1).strip().strip("\"'"'"'") if m else ""))
' "$YAML")"

if [ -z "$COMMAND" ]; then
  echo "ERROR: no hay comando de cobertura detectado en project.yaml (testing.coverage.command vacío)." >&2
  echo "Agregalo a mano en $YAML o corré /skalling-refresh si el proyecto ya tiene un script de coverage." >&2
  exit 1
fi

echo "Corriendo: $COMMAND"
STDOUT_FILE="$(mktemp)"
trap '[ -n "$STDOUT_FILE" ] && rm -f "$STDOUT_FILE"' EXIT
START_TS="$(date +%s)"
if ! (cd "$PROJECT" && bash -c "$COMMAND") > >(tee "$STDOUT_FILE") 2>&1; then
  echo "ERROR: el comando de cobertura falló (exit != 0). No se registra nada." >&2
  exit 1
fi

RESULT="$(python3 - "$PROJECT" "$STDOUT_FILE" "$START_TS" <<'PY'
import json, re, sys
from pathlib import Path

project, stdout_path, start_ts = Path(sys.argv[1]), Path(sys.argv[2]), float(sys.argv[3])
stdout_text = stdout_path.read_text(encoding="utf-8", errors="ignore")

def fresh(path):
    # Un coverage-summary.json de una corrida VIEJA que quedo en disco no
    # cuenta -- solo un artefacto escrito por ESTA corrida es confiable.
    return path.is_file() and path.stat().st_mtime >= start_ts

def istanbul():
    for candidate in ("coverage/coverage-summary.json", "coverage/coverage-final-summary.json"):
        path = project / candidate
        if fresh(path):
            data = json.loads(path.read_text(encoding="utf-8"))
            total = data.get("total", {}).get("lines", {})
            if "pct" in total:
                return {"format": "istanbul", "percent": float(total["pct"]),
                        "lines_covered": total.get("covered"), "lines_total": total.get("total")}
    return None

def python_coverage():
    path = project / "coverage.json"
    if fresh(path):
        data = json.loads(path.read_text(encoding="utf-8"))
        totals = data.get("totals", {})
        if "percent_covered" in totals:
            return {"format": "coverage.py", "percent": float(totals["percent_covered"]),
                     "lines_covered": totals.get("covered_lines"), "lines_total": totals.get("num_statements")}
    return None

def go_cover():
    m = re.search(r"^total:\s*\(statements\)\s*([\d.]+)%", stdout_text, re.MULTILINE)
    if m:
        return {"format": "go-cover", "percent": float(m.group(1)), "lines_covered": None, "lines_total": None}
    return None

result = istanbul() or python_coverage() or go_cover()
if result is None:
    result = {"format": "unknown", "percent": None, "lines_covered": None, "lines_total": None,
               "note": "El comando corrió pero no se reconoció el formato de salida "
                       "(se buscó coverage/coverage-summary.json, coverage.json y "
                       "salida estilo 'go tool cover -func'). Revisá el resultado a mano."}
else:
    result.setdefault("note", None)
print(json.dumps(result))
PY
)"

get_field() {
  python3 -c "
import json, sys
v = json.load(sys.stdin).get(sys.argv[1])
print('' if v is None else v)
" "$1" <<< "$RESULT"
}
FORMAT="$(get_field format)"
PERCENT="$(get_field percent)"
LINES_COVERED="$(get_field lines_covered)"
LINES_TOTAL="$(get_field lines_total)"
NOTE="$(get_field note)"

build_params() {
  python3 -c '
import json, sys
command, format_, percent, covered, total, note = sys.argv[1:]
row = [command, format_,
       None if percent == "" else float(percent),
       None if covered == "" else int(covered),
       None if total == "" else int(total),
       None if note == "" else note]
print(json.dumps(row))
' "$@"
}
PARAMS="$(build_params "$COMMAND" "$FORMAT" "$PERCENT" "$LINES_COVERED" "$LINES_TOTAL" "$NOTE")"
python3 "$SCRIPT_DIR/teamdb_exec.py" --db "$DB" --mode write \
  --sql "INSERT INTO coverage_runs (command, format, percent, lines_covered, lines_total, note) VALUES (?,?,?,?,?,?)" \
  --params "$PARAMS" >/dev/null

if [ -n "$PERCENT" ]; then
  echo "Cobertura: ${PERCENT}% (${LINES_COVERED:-?}/${LINES_TOTAL:-?} líneas, formato $FORMAT)"
else
  echo "El comando corrió, pero no se pudo leer el porcentaje: $NOTE"
fi
