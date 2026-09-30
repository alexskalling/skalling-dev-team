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
AGENTS_DIR="$OPENCODE_DIR/agents"
OVERRIDES_FILE="$OPENCODE_DIR/model-overrides.json"
PROJECT_DIR="${SKALLING_PROJECT_DIR:-$PWD}"
AGENTS=(Alex Jes Jhon Luz Pau Pol Sol Teo)

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

is_known_agent() {
  local name="$1" a
  for a in "${AGENTS[@]}"; do
    [ "$a" = "$name" ] && return 0
  done
  return 1
}

# Aplica (o quita) la linea "model:" en el frontmatter del archivo de agente
# YA INSTALADO, segun lo que diga model-overrides.json ahora mismo. No toca
# el repo de Skalling -- funciona igual si solo tenes la instalacion global,
# sin el checkout del proyecto.
apply_overrides() {
  python3 - "$AGENTS_DIR" "$OVERRIDES_FILE" "$PROJECT_DIR" "$@" <<'PY'
import json, re, sys
from pathlib import Path

agents_dir, overrides_path = Path(sys.argv[1]), Path(sys.argv[2])
project = Path(sys.argv[3])
targets = sys.argv[4:]
directories = [agents_dir]
local = project / ".opencode/agents"
# El checkout fuente genera sus agentes: no contaminarlo con preferencias personales.
if local.is_dir() and not (project / "agents-base").is_dir() and local.resolve() != agents_dir.resolve():
    directories.append(local)

overrides = {}
if overrides_path.is_file():
    overrides = json.loads(overrides_path.read_text(encoding="utf-8") or "{}")

for directory in directories:
  for name in targets:
    agent_file = directory / f"{name}.md"
    if not agent_file.is_file():
        if directory == agents_dir:
            print(f"AVISO: {agent_file} no existe", file=sys.stderr)
        continue
    text = agent_file.read_text(encoding="utf-8")
    header = re.match(r"\A---\r?\n(.*?)\r?\n---(?:\r?\n|$)", text, re.S)
    model = overrides.get(name)
    if not header:
        if text.startswith('---'):
            sys.exit(f"ERROR: frontmatter inválido: {agent_file}")
        if not model:
            continue
        updated = f"---\nmodel: {model}\n---\n" + text
    else:
        lines = [line for line in header[1].splitlines() if not re.match(r'^model:', line)]
        if model:
            lines.append(f"model: {model}")
        updated = "---\n" + "\n".join(lines) + "\n---\n" + text[header.end():]
    if updated != text:
        temporary = agent_file.with_name(agent_file.name + '.models-tmp')
        temporary.write_text(updated, encoding="utf-8")
        temporary.chmod(agent_file.stat().st_mode)
        temporary.replace(agent_file)

PY
}

cmd_show() {
  python3 - "$AGENTS_DIR" "$OVERRIDES_FILE" "$PROJECT_DIR" "${AGENTS[@]}" <<'PYSHOW'
import json, re, sys
from pathlib import Path
agents, config = Path(sys.argv[1]), Path(sys.argv[2])
overrides = json.loads(config.read_text()) if config.is_file() else {}
project = Path(sys.argv[3])
for name in sys.argv[4:]:
    path = agents / f'{name}.md'
    if not path.is_file():
        print(f'{name:<6} (no instalado)')
        continue
    text = path.read_text()
    header = re.match(r'\A---\r?\n(.*?)\r?\n---(?:\r?\n|$)', text, re.S)
    match = re.search(r'(?m)^model:\s*(.+)$', header[1]) if header else None
    metadata = match[1].strip() if match else None
    desired = overrides.get(name)
    shown = desired or metadata or '(default de la sesión)'
    drift = ' [JSON; archivo global desactualizado: ejecutar apply]' if desired and desired != metadata else ''
    local = project / '.opencode/agents' / f'{name}.md'
    local_model = None
    if local.is_file():
        local_header = re.match(r'\A---\r?\n(.*?)\r?\n---(?:\r?\n|$)', local.read_text(), re.S)
        value = re.search(r'(?m)^model:\s*(.+)$', local_header[1]) if local_header else None
        local_model = value[1].strip() if value else '(default de la sesión)'
    local_note = f' | proyecto={local_model}' if local.is_file() else ' | sin override local'
    print(f'{name:<6} {shown}{drift}{local_note}')
print('Configuración en disco; disponibilidad del proveedor y modelo de la sesión activa no verificados.')
PYSHOW
}

cmd_set() {
  local name="${1:?Uso: skalling-models.sh set <Agente> <provider/model-id>}"
  local model="${2:?Uso: skalling-models.sh set <Agente> <provider/model-id>}"
  is_known_agent "$name" || { echo "ERROR: agente desconocido: $name" >&2; usage >&2; exit 2; }
  mkdir -p "$OPENCODE_DIR"
  python3 -c '
import json, sys
from pathlib import Path
path, name, model = Path(sys.argv[1]), sys.argv[2], sys.argv[3]
data = json.loads(path.read_text(encoding="utf-8")) if path.is_file() else {}
data[name] = model
path.write_text(json.dumps(data, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
' "$OVERRIDES_FILE" "$name" "$model"
  apply_overrides "$name"
  echo "$name -> $model"
}

cmd_reset() {
  local name="${1:-}"
  if [ -n "$name" ]; then
    is_known_agent "$name" || { echo "ERROR: agente desconocido: $name" >&2; usage >&2; exit 2; }
  fi
  python3 -c '
import json, sys
from pathlib import Path
path, name = Path(sys.argv[1]), (sys.argv[2] if len(sys.argv) > 2 else "")
data = json.loads(path.read_text(encoding="utf-8")) if path.is_file() else {}
if name:
    data.pop(name, None)
else:
    data = {}
path.write_text(json.dumps(data, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
' "$OVERRIDES_FILE" "$name"
  if [ -n "$name" ]; then
    apply_overrides "$name"
    echo "$name -> default de la sesión"
  else
    apply_overrides "${AGENTS[@]}"
    echo "los 8 agentes vuelven al default de la sesión"
  fi
}

cmd_apply() {
  if [ "${1:-}" = "--project" ] && [ "$#" -eq 2 ]; then
    PROJECT_DIR="$2"
  elif [ "$#" -ne 0 ]; then
    usage >&2
    return 2
  fi
  mkdir -p "$OPENCODE_DIR"
  apply_overrides "${AGENTS[@]}"
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
  show) cmd_show ;;
  fallback) shift; if [ "$#" -eq 0 ]; then set -- show; fi; cmd_fallback "$@" ;;
  set) shift; cmd_set "$@" ;;
  reset) shift; cmd_reset "$@" ;;
  apply) shift; cmd_apply "$@" ;;
  -h|--help) usage ;;
  *) echo "Subcomando desconocido: $1" >&2; usage >&2; exit 2 ;;
esac
