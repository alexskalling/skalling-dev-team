#!/usr/bin/env bash
# Diagnóstico de conflictos de Git; nunca modifica índice, archivos o memoria.
set -euo pipefail
PROJECT="$(pwd)"
while [[ $# -gt 0 ]]; do
    case "$1" in
        --target) PROJECT="${2:?Falta proyecto}"; shift 2 ;;
        --dry-run) shift ;;
        --help|-h) echo 'Uso: merge-helper.sh [--target proyecto] [--dry-run]'; exit 0 ;;
        *) echo "Argumento desconocido: $1" >&2; exit 2 ;;
    esac
done
python3 - "$PROJECT" <<'PY'
import subprocess, sys
project = sys.argv[1]
def git(*args):
    return subprocess.run(['git', '-C', project, *args], capture_output=True, check=True).stdout
try:
    git('rev-parse', '--show-toplevel')
    conflicts = [p.decode() for p in git('diff', '--name-only', '--diff-filter=U', '-z').split(b'\0') if p]
except subprocess.CalledProcessError as exc:
    sys.exit('ERROR: no se pudo consultar Git: ' + exc.stderr.decode().strip())
if not conflicts:
    print('Sin conflictos sin resolver en el índice de Git. No se predicen conflictos entre ramas.')
for path in conflicts:
    print('CONFLICTO: ' + path)
    if path.startswith('db/teamdb/'):
        print('  Dump de TeamDB: conservar la base local; revisar ambas versiones antes de importar. No ejecutar SQL del conflicto.')
    elif path == 'AGENTS.md' or path.startswith('.opencode/'):
        print('  Configuración/memoria: comparar ambas versiones y conservar personalizaciones; no regenerar a ciegas.')
    else:
        print('  Archivo del proyecto: resolver según la intención de ambas ramas.')
if conflicts:
    print('Diagnóstico completo: hay conflictos pendientes. No se resolvió ni se commiteó nada.')
PY
