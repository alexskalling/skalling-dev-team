#!/usr/bin/env bash
# Refresh explícito: contexto, skills e inventarios; reporta reparaciones pendientes.
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT="${SKALLING_ROOT:-$(dirname "$SCRIPT_DIR")}"
PROJECT="${2:-$(pwd)}"
MODE="${1:---check}"
case "$MODE" in --check|--apply) ;; *) echo 'Uso: skalling-refresh.sh --check|--apply [proyecto]' >&2; exit 2 ;; esac
PROJECT="$(cd "$PROJECT" && pwd -P)"
result=0
if [[ "$MODE" == --apply ]]; then
    bash "$ROOT/bootstrap-context.sh" --target "$PROJECT" --force || result=$?
    python3 "$SCRIPT_DIR/skalling_skills.py" repair --root "$ROOT" --target "$PROJECT/.opencode" || result=1
    python3 "$SCRIPT_DIR/skalling_skills.py" sync --project "$PROJECT" || result=1
else
    bash "$ROOT/bootstrap-context.sh" --target "$PROJECT" --only-detection || result=$?
fi
python3 "$SCRIPT_DIR/skalling_skills.py" audit --root "$ROOT" --project "$PROJECT" || result=1
python3 - "$PROJECT" "$SCRIPT_DIR" <<'PYCONTEXT' || result=1
import sqlite3, sys
from pathlib import Path
sys.path.insert(0, sys.argv[2])
from skalling_context import source_fingerprint
project = Path(sys.argv[1])
try:
    with sqlite3.connect((project/'.opencode/context/team.db').as_uri()+'?mode=ro', uri=True) as db:
        meta = dict(db.execute("SELECT key,value FROM schema_meta WHERE key IN ('project_readiness','bootstrap.sources') OR key LIKE 'bootstrap.pending.%'"))
    pending = [k for k in meta if k.startswith('bootstrap.pending.')]
    if meta.get('project_readiness') != 'initialized' or meta.get('bootstrap.sources') != source_fingerprint(project) or pending:
        sys.exit('Contexto incompleto, cambiado o con observaciones pendientes: ' + ', '.join(pending))
    print('Contexto: fuentes vigentes; comprensión del pedido se verifica en cada workflow.')
except (OSError, sqlite3.Error) as error:
    sys.exit('Contexto no verificado: ' + str(error))
PYCONTEXT
python3 "$SCRIPT_DIR/skalling-runtime.py" check --root "$ROOT" --target "$PROJECT/.opencode" || result=1
if [[ "$result" == 0 ]]; then
    echo 'Refresh: contexto y skills comprobados; runtime local coincide con la versión consultada.'
else
    echo 'Refresh incompleto: revisar los hallazgos anteriores. No se declara el proyecto listo.' >&2
fi
exit "$result"
