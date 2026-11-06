"""Run configured coverage with bounded time/output; emit execution metadata."""
import json
import os
from pathlib import Path
import signal
import subprocess
import sys
import time

from skalling_config import testing_config
from skalling_process import run_bounded, _cancel

project, output_path = Path(sys.argv[1]).resolve(), Path(sys.argv[2])
config = testing_config(project/'.opencode/project.yaml')
timeout = max(1, min(config.get('timeout_seconds', 900), 3600))
signal.signal(signal.SIGTERM, _cancel)
signal.signal(signal.SIGINT, _cancel)
started = time.time()
timed_out = False
try:
    code, output = run_bounded(['bash', '-c', config['coverage']], project, os.environ.copy(), timeout)
    code = code if code >= 0 else 128 - code
    note = f'El comando terminó con exit={code}.'
except subprocess.TimeoutExpired as error:
    timed_out, code = True, 124
    output = (error.output or b'').decode('utf-8', 'replace')
    note = f'Cobertura cancelada tras {timeout} segundos; se terminó su grupo de procesos.'
output_path.write_text(output, encoding='utf-8')
print(json.dumps({'started_at': started, 'exit_code': code, 'timed_out': timed_out, 'note': note}))
