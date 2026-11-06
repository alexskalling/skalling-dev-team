#!/usr/bin/env bash
# skalling-models.sh — asigna un modelo de OpenCode a cada agente de Skalling,
# independiente por agente (usa el campo "model:" del frontmatter de cada
# archivo de agente instalado -- OpenCode lo aplica por archivo desde que
# soporta agentes custom en markdown, sin el límite viejo de compartir uno de
# 4 roles genéricos entre varios agentes).
#
# Los overrides quedan en model-overrides.json, en la instalación global (NO
# en el repo de Skalling) -- sobreviven a un reinstall/update porque
# install-global.sh los vuelve a aplicar después de regenerar los agentes
# desde agents-base/. Un agente sin override usa el modelo default de la
# sesión de OpenCode, como hoy.
#
# Uso:
#   skalling-models.sh show                      # modelo actual de cada agente
#   skalling-models.sh set <Agente> <provider/model-id>
#   skalling-models.sh reset [Agente]             # sin agente: resetea los 8
#   skalling-models.sh apply                      # reaplica model-overrides.json
#                                                  # (lo usa install-global.sh tras
#                                                  # reinstalar, para no perder overrides)
#
# set/reset/apply sincronizan el JSON con los agentes globales y del proyecto
# actual. Reiniciar OpenCode carga los cambios; una sesión activa conserva su
# selección. apply --project permite indicar otro proyecto explícitamente.
#
# Corré "opencode models" para ver los IDs disponibles en tu instalación.
set -euo pipefail

OPENCODE_DIR="${SKALLING_OPENCODE_DIR:-${OPENCODE_CONFIG_DIR:-${XDG_CONFIG_HOME:-$HOME/.config}/opencode}}"
PROJECT_DIR="${SKALLING_PROJECT_DIR:-$PWD}"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

usage() {
  cat <<'HELP'
Uso:
  skalling-models.sh show
  skalling-models.sh set <Agente> <provider/model-id>
  skalling-models.sh reset [Agente]
  skalling-models.sh apply [--project <ruta>]
  skalling-models.sh fallback show|reset [Agente]
  skalling-models.sh fallback set <Agente> <provider/model> [otros modelos...]
  skalling-models.sh fallback timeout <Agente> <total-segundos> <silencio-segundos>

Agentes: Alex Jes Jhon Luz Pau Pol Sol Teo
HELP
}

cmd_fallback() {
  mkdir -p "$OPENCODE_DIR"
  python3 - "$OPENCODE_DIR/model-fallbacks.json" "$@" <<'PYCONFIG'
import json, os, re, sys, tempfile
from pathlib import Path
path, action, *args = sys.argv[1:]
path = Path(path)
data = json.loads(path.read_text()) if path.exists() else {}
roles = {'Alex', 'Jes', 'Jhon', 'Luz', 'Pau', 'Pol', 'Sol', 'Teo'}
try:
    if action == 'show' and not args:
        print(json.dumps(data, indent=2, ensure_ascii=False))
        print('Runtime requerido: OpenCode 2.0.18. Reiniciar OpenCode después de cambiar la política.')
        sys.exit(0)
    role = args[0] if args else None
    if role is not None and role not in roles:
        raise ValueError('agente desconocido')
    if action == 'set' and role:
        models = args[1:]
        if not 1 <= len(models) <= 3 or len(set(models)) != len(models) or any(
            not re.fullmatch(r'[A-Za-z0-9_.-]+/[A-Za-z0-9_./:-]+(?:#[A-Za-z0-9_.-]+)?', m) for m in models):
            raise ValueError('indicar entre 1 y 3 modelos provider/model distintos, obtenidos de opencode models')
        data[role] = {**data.get(role, {}), 'models': models}
    elif action == 'reset' and len(args) <= 1:
        if role: data.pop(role, None)
        else: data = {}
    elif action == 'timeout' and len(args) == 3 and role in data:
        total, silence = map(int, args[1:])
        if not 1 <= silence <= total <= 600:
            raise ValueError('plazos: 1 <= silencio <= total <= 600 segundos')
        data[role].update(timeoutMs=total * 1000, chunkTimeoutMs=silence * 1000)
    else:
        raise ValueError('uso: fallback show | set Agente provider/model... | reset [Agente] | timeout Agente total silencio')
    fd, temporary = tempfile.mkstemp(dir=path.parent, prefix='.model-fallbacks-')
    try:
        with os.fdopen(fd, 'w') as output:
            output.write(json.dumps(data, indent=2, ensure_ascii=False) + '\n')
        os.replace(temporary, path)
    finally:
        if os.path.exists(temporary): os.unlink(temporary)
    print('Política guardada. Reiniciar OpenCode para activarla; no cambia el modelo principal.')
except (ValueError, TypeError) as error:
    sys.exit(f'ERROR: {error}')
PYCONFIG
}

case "${1:-show}" in
  show) if [ "$#" -gt 0 ]; then shift; fi; python3 "$SCRIPT_DIR/skalling_models.py" "$OPENCODE_DIR" "$PROJECT_DIR" show "$@" ;;
  fallback) shift; if [ "$#" -eq 0 ]; then set -- show; fi; cmd_fallback "$@" ;;
  set|reset|apply) action="$1"; shift; python3 "$SCRIPT_DIR/skalling_models.py" "$OPENCODE_DIR" "$PROJECT_DIR" "$action" "$@" ;;
  -h|--help) usage ;;
  *) echo "Subcomando desconocido: $1" >&2; usage >&2; exit 2 ;;
esac
