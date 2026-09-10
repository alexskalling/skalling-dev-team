#!/usr/bin/env bash
# Session identity is supplied by the OpenCode plugin, not guessed from cwd.
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
python3 - "$SCRIPT_DIR/skalling-goal.py" "${SKALLING_GOAL_PROJECT:-$PWD}" "${SKALLING_GOAL_SESSION:-}" "$@" <<'PY'
import json, subprocess, sys
script, project, session, *args = sys.argv[1:]
action = args[0] if args else 'status'
if action not in ('status', 'checkpoint', 'block', 'commit'):
    raise SystemExit('Usa /skalling-goal para iniciar, pausar, retomar o cancelar; no simular autorización con Bash.')
payload = {}
if action == 'checkpoint': payload['summary'] = args[1] if len(args) > 1 else ''
if action == 'block': payload['reason'] = args[1] if len(args) > 1 else 'Falta decisión del usuario'
if action == 'commit':
    payload = {'message': args[1] if len(args) > 1 else '', 'files': args[2:]}
request = {'project': project, 'session': session, 'action': action, 'payload': payload}
raise SystemExit(subprocess.run([sys.executable, script], input=json.dumps(request), text=True).returncode)
PY
