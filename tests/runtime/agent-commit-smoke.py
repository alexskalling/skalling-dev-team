"""Opt-in acceptance with real, configured OpenCode agents (provider usage).

Run after installing the current engine, workflow plugin and Teo protocol globally.
No remote, auto-approved permissions or disabled hooks. Keeps the isolated repo
and event log for inspection; failure or timeout never counts as a successful run.
"""
import json
import os
from pathlib import Path
import re
import shutil
import signal
import sqlite3
import subprocess
import tempfile
import time

SOURCE = Path(__file__).resolve().parents[2]
GLOBAL = Path.home() / '.config/opencode'
BINARY = shutil.which('opencode')
assert BINARY, 'OpenCode is required'
for name in ('scripts/skalling-workflow.py', 'plugins/lib/workflow.mjs', 'plugins/lib/git-guard.mjs'):
    assert (GLOBAL / name).read_bytes() == (SOURCE / name).read_bytes(), f'Install current {name} globally first'
alex = (GLOBAL / 'agents/Alex.md').read_text(encoding='utf-8')
model = re.search(r'^model:\s*(\S+)\s*$', alex.split('---', 2)[1], re.MULTILINE)
assert model, 'Alex must have a configured model'
root = Path(tempfile.mkdtemp(prefix='skalling-agent-commit-'))
print(f'Fixture: {root}', flush=True)
(root / 'tests').mkdir()
(root / 'app.py').write_text('def normalize_label(value):\n    return value\n', encoding='utf-8')
(root / 'tests/check.py').write_text('''import sys
from pathlib import Path
sys.path.insert(0, str(Path(__file__).resolve().parents[1]))
from app import normalize_label
assert normalize_label("  hola mundo  ") == "hola mundo"
assert normalize_label("a  b") == "a  b"
assert normalize_label("   ") == ""
print("PASS 3 normalization cases")
''', encoding='utf-8')
(root / '.gitignore').write_text('.opencode/\n.codegraph/\n__pycache__/\n', encoding='utf-8')
(root / 'README.md').write_text('# Python fixture\nnormalize_label preserves internal spaces. No dependencies.\n', encoding='utf-8')


def run(argv):
    return subprocess.run(argv, cwd=root, check=True, capture_output=True, text=True)


for args in (['init', '-q'], ['config', 'user.name', 'Skalling acceptance'],
             ['config', 'user.email', 'fixture@example.invalid'], ['add', '.'],
             ['commit', '-qm', 'test: base de aceptación aislada']):
    run(['git', *args])
baseline = run(['git', 'rev-parse', 'HEAD']).stdout.strip()
runtime = root / '.opencode'
runtime.mkdir()
for name, src in [('agents', GLOBAL / 'agents'), ('scripts', SOURCE / '.opencode/scripts'),
                  ('plugins', SOURCE / 'plugins'), ('hooks', SOURCE / 'scripts/hooks')]:
    shutil.copytree(src, runtime / name, ignore=shutil.ignore_patterns('__pycache__', '*.pyc'))
(runtime / 'project.yaml').write_text('''project:
  name: acceptance-fixture
stack:
  language: python
testing:
  fast:
    available: true
    command: "python3 tests/check.py"
  unit:
    available: true
    command: "python3 tests/check.py"
''', encoding='utf-8')
shutil.copy2(SOURCE / 'templates/opencode.json', runtime / 'opencode.json')
run(['bash', str(SOURCE / 'scripts/teamdb-init.sh'), str(root)])
with sqlite3.connect(runtime / 'context/team.db') as db:
    db.execute("INSERT OR REPLACE INTO schema_meta(key,value) VALUES('project_readiness','initialized')")
    db.execute("INSERT INTO concepts(slug,title,body_md,category,updated_at) VALUES(?,?,?,?,datetime('now'))",
               ('project-summary', 'Acceptance fixture', 'Python without dependencies. app.py implements '
                'normalize_label; tests/check.py checks three cases. No UI or deployment.', 'general'))
hook = root / '.git/hooks/pre-commit'
hook.write_text('#!/bin/sh\nexec python3 "' + str(runtime / 'hooks/git-gate.py') + '" pre-commit\n', encoding='utf-8')
hook.chmod(0o755)
for extra in ([], ['--check']):
    run(['python3', str(SOURCE / 'scripts/skalling-project-config.py'), str(root), *extra])
request = ('Corrige normalize_label en app.py: debe quitar los espacios exteriores, conservar los '
           'interiores y devolver vacío para una entrada de sólo espacios. Módulo Python sin dependencias; '
           'tests/check.py contiene los tres casos. Implementa, verifica y deja un commit local con '
           'los hooks activos. Ejecuta tú y tu equipo lo necesario: no me pidas correr comandos ni '
           'hacer el commit. No autorizo ningún push. Al terminar informa el SHA y las pruebas.')
started = time.monotonic()
with (runtime / 'acceptance-events.jsonl').open('w') as out, (runtime / 'acceptance-stderr.log').open('w') as err:
    process = subprocess.Popen([BINARY, 'run', '--standalone', '--agent', 'Alex', '--model',
                                model.group(1).strip('"\''), '--format', 'json',
                                '--title', 'Aceptación autónoma de commit local', request],
                               cwd=root, env={**os.environ, 'PWD': str(root)}, stdout=out, stderr=err, start_new_session=True)
    try:
        code = process.wait(timeout=600)
    except subprocess.TimeoutExpired:
        os.killpg(process.pid, signal.SIGINT)
        try:
            process.wait(timeout=10)
        except subprocess.TimeoutExpired:
            os.killpg(process.pid, signal.SIGKILL)
            process.wait()
        raise AssertionError(f'Acceptance timed out; inspect {runtime}') from None
assert code == 0, f'OpenCode exited {code}; inspect {runtime}'
sha = run(['git', 'rev-parse', 'HEAD']).stdout.strip()
assert sha != baseline, 'Agent did not create a commit'
assert not run(['git', 'status', '--porcelain']).stdout, 'Candidate not clean after commit'
assert not run(['git', 'remote']).stdout, 'Fixture must have no remote'
assert run(['git', 'show', 'HEAD:tests/check.py']).stdout == run(['git', 'show', baseline + ':tests/check.py']).stdout, 'Acceptance test changed'
assert run(['python3', 'tests/check.py']).stdout.strip() == 'PASS 3 normalization cases'
with sqlite3.connect(runtime / 'context/team.db') as db:
    workflows = [json.loads(row[0]) for row in db.execute('SELECT body FROM agent_workflows')]
    committed = [w for w in workflows if w.get('local_commit_result', {}).get('sha') == sha]
    assert len(committed) == 1 and committed[0]['state'] == 'completed', 'Commit/cycle not recorded'
    state = committed[0]
    assert not re.search(r'\b(commit|sha|push|hooks)\b', json.dumps(state['outcomes']), re.IGNORECASE), (
        'Product outcomes must not claim a commit before it exists')
    assert any(c['exit_code'] != 0 for c in state.get('implementation_checks', [])
               if c['exit_code'] is not None), 'No recorded RED'
    assert state['coverage'] and all(c['exit_code'] == 0 for c in state['checks']), 'Unverified outcome'
    assert db.execute('SELECT count(*) FROM receipts WHERE exit_code=0').fetchone()[0], 'No receipt'
    actors = {row[0] for row in db.execute('SELECT DISTINCT actor FROM agent_workflow_events')}
    assert actors <= {'alex', 'teo', 'auto'}, 'A complete configured check should not add another agent merely to commit: ' + str(actors)
print(json.dumps({'sha': sha, 'elapsed_seconds': round(time.monotonic() - started),
                  'workflow': state['id'], 'actors': sorted(actors), 'fixture': str(root), 'push': 'not authorized'}, ensure_ascii=False))
