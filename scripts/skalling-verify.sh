#!/usr/bin/env bash
# skalling-verify.sh — corre el comando de test real del proyecto (detectado
# en project.yaml por bootstrap-context.sh, nunca inventado) y devuelve su
# exit code real. Lo usa teamdb-seal-receipt.sh cuando el agente que sella es
# jhon (test verifier): antes de este script, sellar un receipt de jhon
# aceptaba el exit code que el propio caller le pasara por variable de
# entorno (default 0) sin correr nada — un "confía en mí" que nadie
# verificaba. Con esto, si el test real del proyecto falla, el receipt queda
# con exit_code != 0 y en_review->approved (que exige un receipt exit_code=0
# de jhon) se bloquea solo, sin depender de que alguien se acuerde de correr
# el test a mano.
#
# Uso: skalling-verify.sh <project>
# Exit codes:
#   0 = el comando de test corrió y pasó
#   1 = el comando de test corrió y falló
#   2 = no hay comando de test configurado en project.yaml (no es un fail:
#       Skalling no puede inventar un comando que el proyecto no declaró)
set -euo pipefail

PROJECT="${1:?Uso: skalling-verify.sh <project>}"
YAML="$PROJECT/.opencode/project.yaml"

if [ ! -f "$YAML" ]; then
  echo "SIN-CONFIGURAR: no existe $YAML (correr /skalling-init primero)" >&2
  exit 2
fi

COMMAND="$(python3 -c '
import re, sys
text = open(sys.argv[1], encoding="utf-8").read()
# Aisla el bloque de "unit:" (sus hijos, indentados MAS que "unit:" mismo)
# y busca available:/command: DENTRO de ese bloque, sin asumir orden ni
# adyacencia -- una version anterior exigia "available:" pegado justo antes
# de "command:", y con las claves en el orden real que genera
# bootstrap-context.py (o un comentario de por medio) el regex no matcheaba
# nada y silenciosamente se trataba como "sin configurar".
m = re.search(r"unit:[ \t]*\n((?:[ \t]{3,}\S.*\n?)*)", text)
block = m.group(1) if m else ""
avail_m = re.search(r"available:\s*(\w+)", block)
cmd_m = re.search(r"command:\s*(.*)", block)
available = bool(avail_m) and avail_m.group(1).strip().lower() == "true"
command = cmd_m.group(1).strip().strip("\"'"'"'") if cmd_m else ""
print(command if (available and command) else "")
' "$YAML")"

if [ -z "$COMMAND" ]; then
  echo "SIN-CONFIGURAR: no hay comando de test detectado en project.yaml (testing.unit.available es false, o testing.unit.command está vacío)." >&2
  exit 2
fi

echo "Corriendo (verificación real, no confianza): $COMMAND" >&2
if (cd "$PROJECT" && bash -c "$COMMAND"); then
  echo "OK: $COMMAND (exit 0)" >&2
  exit 0
else
  RC=$?
  echo "FALLO: $COMMAND (exit $RC)" >&2
  exit 1
fi
