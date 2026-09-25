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
# Corré "opencode models" para ver los IDs disponibles en tu instalación.
set -euo pipefail

OPENCODE_DIR="${SKALLING_OPENCODE_DIR:-$HOME/.config/opencode}"
AGENTS_DIR="$OPENCODE_DIR/agents"
OVERRIDES_FILE="$OPENCODE_DIR/model-overrides.json"
AGENTS=(Alex Jes Jhon Luz Pau Pol Sol Teo)

usage() {
  cat <<'HELP'
Uso:
  skalling-models.sh show
  skalling-models.sh set <Agente> <provider/model-id>
  skalling-models.sh reset [Agente]
  skalling-models.sh apply

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
  python3 - "$AGENTS_DIR" "$OVERRIDES_FILE" "$@" <<'PY'
import json, re, sys
from pathlib import Path

agents_dir, overrides_path = Path(sys.argv[1]), Path(sys.argv[2])
targets = sys.argv[3:]

overrides = {}
if overrides_path.is_file():
    overrides = json.loads(overrides_path.read_text(encoding="utf-8") or "{}")

for name in targets:
    agent_file = agents_dir / f"{name}.md"
    if not agent_file.is_file():
        print(f"AVISO: {agent_file} no existe, se salta", file=sys.stderr)
        continue
    text = agent_file.read_text(encoding="utf-8")
    parts = text.split("---", 2)
    if len(parts) < 3:
        print(f"AVISO: {agent_file} no tiene frontmatter reconocible, se salta", file=sys.stderr)
        continue
    front = parts[1]
    front = re.sub(r"(?m)^model:.*\n", "", front)
    model = overrides.get(name)
    if model:
        # Despues de "mode:" si existe, si no al principio del frontmatter.
        if re.search(r"(?m)^mode:.*$", front):
            front = re.sub(r"(?m)^(mode:.*)$", r"\1\nmodel: " + model, front, count=1)
        else:
            front = f"\nmodel: {model}" + front
    parts[1] = front
    agent_file.write_text("---".join(parts), encoding="utf-8")
PY
}

cmd_show() {
  local name f current
  for name in "${AGENTS[@]}"; do
    f="$AGENTS_DIR/$name.md"
    if [ ! -f "$f" ]; then
      printf '%-6s (no instalado)\n' "$name"
      continue
    fi
    current="$(grep -m1 -E '^model:' "$f" 2>/dev/null | sed -E 's/^model:[[:space:]]*//' || true)"
    if [ -n "$current" ]; then
      printf '%-6s %s\n' "$name" "$current"
    else
      printf '%-6s (default de la sesión)\n' "$name"
    fi
  done
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
  mkdir -p "$OPENCODE_DIR"
  apply_overrides "${AGENTS[@]}"
}

case "${1:-show}" in
  show) cmd_show ;;
  set) shift; cmd_set "$@" ;;
  reset) shift; cmd_reset "$@" ;;
  apply) cmd_apply ;;
  -h|--help) usage ;;
  *) echo "Subcomando desconocido: $1" >&2; usage >&2; exit 2 ;;
esac
