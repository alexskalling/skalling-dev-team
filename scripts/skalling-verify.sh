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
# Los helpers Python no dejan bytecode en .opencode/scripts: un .pyc nuevo
# durante la verificación aparecía como cambio sin stagear y la aprobación
# se rechazaba (auditoría 2026-09-27).
export PYTHONDONTWRITEBYTECODE=1
# pnpm 11 can auto-install before running a test. Verification must not
# resolve or upgrade dependencies as a side effect of `run`/`exec`.
export PNPM_CONFIG_VERIFY_DEPS_BEFORE_RUN=false
export npm_config_verify_deps_before_run=false

PROJECT="${1:?Uso: skalling-verify.sh <project>}"
YAML="$PROJECT/.opencode/project.yaml"

if [ ! -f "$YAML" ]; then
  echo "SIN-CONFIGURAR: no existe $YAML (correr /skalling-init primero)" >&2
  exit 2
fi

# Parser único de project.yaml (skalling_config.py): escalares YAML con
# comillas y escapes, igual que el motor y el bootstrap.
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
COMMAND="$(PYTHONPATH="$SCRIPT_DIR${PYTHONPATH:+:$PYTHONPATH}" python3 -m skalling_config "$YAML" unit)"

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
