#!/usr/bin/env python3
"""Conservative local verification. Unknown/shared inputs use the complete suite.

The mapping is explicit: a textual reference is not proof of test coverage.
--plan prints the decision without executing it. Tests execute with the same
Python environment as run-all, with bounded process groups and fail-fast output.
"""
import argparse
import json
import os
from pathlib import Path
import signal
import subprocess
import sys
import time

ROOT = Path(__file__).resolve().parents[1]
IMPACT = {
    'plugins/lib/git-guard.mjs': ['tests/git-guard-plugin.test.mjs', 'tests/permission-bypass.test.mjs',
                                 'tests/workflow-plugin.test.mjs', 'tests/data-safety-v2.test.mjs'],
    'plugins/lib/workflow.mjs': ['tests/workflow-plugin.test.mjs', 'tests/permission-bypass.test.mjs',
                                'tests/project-test-command-permission.test.py'],
    'plugins/lib/data-safety.mjs': ['tests/data-safety-plugin.test.mjs', 'tests/data-safety-v2.test.mjs',
                                   'tests/permission-bypass.test.mjs'],
    'scripts/teamdb-context.sh': ['tests/context-regressions.test.py', 'tests/teamdb-context-capsule.test.sh',
                                'tests/teamdb-context-issue8.test.sh', 'tests/scripts-parity.test.sh'],
    'scripts/skalling-workflow.py': ['tests/workflow-engine.test.py', 'tests/workflow-worktree.test.py',
                                   'tests/workflow-git-gate-bridge.test.py', 'tests/scripts-parity.test.sh'],
    'tests/run-selected.py': ['tests/test-selection.test.py'],
}


def select(files):
    selected = set()
    for name in files:
        path = Path(name)
        if path.is_absolute() or '..' in path.parts:
            return {'full': True, 'reason': 'scope outside project', 'tests': []}
        name = path.as_posix()
        if name.startswith('.opencode/scripts/'):
            name = 'scripts/' + path.name
        if name in IMPACT:
            selected.update(IMPACT[name])
        elif name.startswith('tests/') and '.test.' in name and (ROOT / name).is_file():
            selected.add(name)
        else:
            return {'full': True, 'reason': 'unmapped or shared input: ' + name, 'tests': []}
    if not selected:
        return {'full': True, 'reason': 'no explicit scope', 'tests': []}
    return {'full': False, 'reason': 'explicit impact map', 'tests': sorted(selected)}


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--plan', action='store_true')
    parser.add_argument('files', nargs='*')
    args = parser.parse_args()
    plan = select(args.files)
    if args.plan:
        print(json.dumps(plan, ensure_ascii=False))
        return 0
    env = os.environ.copy()
    python = env.get('PYTHON') or (str(ROOT / '.venv/bin/python') if (ROOT / '.venv/bin/python').exists() else sys.executable)
    env['PATH'] = str(Path(python).parent) + os.pathsep + env['PATH']
    if plan['full']:
        print('Verificación completa: ' + plan['reason'], flush=True)
        return subprocess.call(['bash', 'tests/run-all.sh'], cwd=ROOT, env=env)
    for test in plan['tests']:
        argv = (['node', '--test'] if test.endswith('.mjs') else [python] if test.endswith('.py') else ['bash']) + [test]
        start = time.monotonic()
        proc = subprocess.Popen(argv, cwd=ROOT, env=env, start_new_session=True)
        try:
            code = proc.wait(timeout=int(env.get('SKALLING_TEST_TIMEOUT_EACH', '300')))
        except (subprocess.TimeoutExpired, KeyboardInterrupt):
            if hasattr(os, 'killpg'):
                os.killpg(proc.pid, signal.SIGKILL)
            else:
                proc.kill()
            proc.wait()
            code = 124
        print(f'{test}: exit={code} duration={time.monotonic() - start:.3f}s', flush=True)
        if code:
            return code
    return 0


if __name__ == '__main__':
    sys.exit(main())
