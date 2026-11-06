#!/usr/bin/env python3
"""Run real agent tasks, graded by an external oracle, never by its final prose.

Example: python3 tests/evals/run.py --output /path/results.json --case empty-total
Requires an installed OpenCode runtime/provider. Model selection is inherited.
Fixtures and logs remain beside the report. No passing result is invented when
runtime setup, permissions or provider access fail. Not part of ordinary CI.
"""
import argparse
import hashlib
import importlib.util
import json
import os
from pathlib import Path
import shutil
import signal
import sqlite3
import subprocess
import sys
import time

ROOT = Path(__file__).resolve().parents[2]
CASES = json.loads(Path(__file__).with_name('tasks.json').read_text())


def grade(case, project):
    result = subprocess.run([sys.executable, '-B', '-c', case['oracle']], cwd=project,
                            capture_output=True, text=True, timeout=15)
    return {'passed': result.returncode == 0, 'oracle_exit_code': result.returncode,
            'diagnostic': result.stderr[-2000:]}


def task_passed(record):
    """Behavior, scope and authorization always apply; team mode also requires closure."""
    return (record.get('behavior_passed') is True
            and record.get('agent_exit_code') == 0
            and record.get('diff_scope_passed') is True
            and record.get('authorization_passed') is True
            and (record.get('mode', 'team') == 'single' or record.get('workflow_state') == 'completed'))


def measure(project, case=None, baseline_head=None):
    """Collect harness facts from its own ledger; never infer success from prose."""
    db_path = project / '.opencode/context/team.db'
    metrics = {}
    workflow = {}
    try:
        with sqlite3.connect('file:' + str(db_path) + '?mode=ro', uri=True) as db:
            row = db.execute(
                'SELECT request_id, route, handoffs, duration_ms, outcome, tokens_input, '
                'tokens_output, retries, tokens_cache_read, cost FROM workflow_metrics ORDER BY started_at DESC LIMIT 1'
            ).fetchone()
            if row:
                keys = ('request_id', 'route', 'handoffs', 'duration_seconds', 'outcome',
                        'tokens_input', 'tokens_output', 'retries', 'tokens_cache_read', 'cost')
                metrics = dict(zip(keys, row))
                if metrics.get('duration_seconds') is not None:
                    metrics['duration_seconds'] = round(metrics['duration_seconds'] / 1000, 3)
            row = db.execute('SELECT body FROM agent_workflows WHERE id=?',
                             (metrics.get('request_id'),)).fetchone()
            if row:
                workflow = json.loads(row[0])
    except (OSError, sqlite3.Error, json.JSONDecodeError):
        pass
    changed = subprocess.run(['git', 'status', '--porcelain', '--untracked-files=all'], cwd=project,
                             capture_output=True, text=True)
    base = subprocess.run(['git', 'rev-list', '--max-parents=0', 'HEAD'], cwd=project, capture_output=True, text=True)
    diff = subprocess.run(['git', 'diff', '--name-only', base.stdout.strip(), '--'], cwd=project,
                          capture_output=True, text=True) if base.returncode == 0 else base
    head = subprocess.run(['git', 'rev-parse', 'HEAD'], cwd=project, capture_output=True, text=True)
    expected_head = baseline_head or base.stdout.strip()
    allowed_files = set((case or {}).get('allowed_files', ['app.py']))
    changed_files = sorted({line[3:] for line in changed.stdout.splitlines() if len(line) > 3}
                           | set(diff.stdout.splitlines()))
    return {
        'metrics': metrics,
        'authorization_passed': head.returncode == 0 and bool(expected_head) and head.stdout.strip() == expected_head,
        'workflow_commit_policy': workflow.get('commit_policy'),
        'workflow_state': workflow.get('state'),
        'workflow_deliveries': workflow.get('delivery_number'),
        'workflow_last_rejection': workflow.get('last_rejection'),
        'changed_files': changed_files,
        'human_corrections': workflow.get('human_corrections'),
        'user_acceptance': workflow.get('user_acceptance'),
        'outcome_coverage': workflow.get('coverage'),
        'diff_scope_passed': changed.returncode == 0 and diff.returncode == 0 and set(changed_files) <= allowed_files,
    }


def prepare(case, project, mode='team'):
    project.mkdir(parents=True)
    (project / 'app.py').write_text(case['source'])
    for name, content in case.get('fixture_files', {}).items():
        target = project / name
        target.parent.mkdir(parents=True, exist_ok=True)
        target.write_text(content)
    (project / 'README.md').write_text('# Evaluation fixture\nSmall Python utility; preserve its public API.\n')
    (project / '.gitignore').write_text('.opencode/\n__pycache__/\nopencode.json\ndb/teamdb/\n')
    subprocess.run(['git', 'init', '-q'], cwd=project, check=True)
    subprocess.run(['git', '-c', 'user.name=Eval', '-c', 'user.email=eval@localhost',
                    'add', 'app.py', 'README.md', '.gitignore', *case.get('fixture_files', {})], cwd=project, check=True)
    subprocess.run(['git', '-c', 'user.name=Eval', '-c', 'user.email=eval@localhost',
                    'commit', '-qm', 'fixture baseline'], cwd=project, check=True)
    baseline_head = subprocess.check_output(['git', 'rev-parse', 'HEAD'], cwd=project, text=True).strip()
    config = project / '.opencode'
    config.mkdir()
    # Use the current checkout's prompts and plugins, not stale installed copies.
    (config / 'agents').mkdir()
    for name in ('Alex', 'Pol', 'Sol', 'Teo', 'Jhon', 'Luz', 'Pau', 'Jes'):
        rendered = subprocess.run(['bash', str(ROOT / 'scripts/render-agent.sh'),
                                   str(ROOT / 'agents-base' / (name + '.md'))],
                                  capture_output=True, encoding='utf-8', check=True, timeout=30)
        (config / 'agents' / (name + '.md')).write_text(rendered.stdout, encoding='utf-8')
    shutil.copytree(ROOT / 'plugins', config / 'plugins')
    shutil.copytree(ROOT / 'scripts', config / 'scripts', ignore=shutil.ignore_patterns('__pycache__'))
    shutil.copytree(ROOT / 'sql', config / 'sql')
    shutil.copyfile(ROOT / 'templates/opencode.json', project / 'opencode.json')
    if mode == 'single':
        config_path = project / 'opencode.json'
        settings = json.loads(config_path.read_text())
        settings.setdefault('permission', {}).update(task='deny', subagent='deny')
        config_path.write_text(json.dumps(settings, indent=2))

    subprocess.run(['bash', str(ROOT / 'scripts/teamdb-init.sh'), str(project)], check=True, capture_output=True)
    # A real context record via the normal helper; no agent claims fabricated.
    subprocess.run(['bash', str(ROOT / 'scripts/teamdb-memory.sh'), '--project', str(project),
                    'concept', 'project-summary', 'Fixture', case.get('memory', 'Python utility with an existing app.py API')],
                   check=True, capture_output=True)
    import sqlite3
    with sqlite3.connect(config / 'context/team.db') as db:
        db.execute("INSERT OR REPLACE INTO schema_meta(key,value) VALUES('project_readiness','initialized')")
    (config / 'project.yaml').write_text('testing:\n  unit:\n    available: true\n    command: "python3 -B -m py_compile app.py"\n')
    (project / '.gitignore').write_text('.opencode/\n__pycache__/\nopencode.json\ndb/teamdb/\n')

    return baseline_head


def logged_usage(log, since, until):
    """Use runtime session IDs from events, never infer tokens from prose/bytes."""
    sessions = set()
    for line in log.read_text().splitlines():
        try:
            event = json.loads(line)
        except ValueError:
            continue
        if not isinstance(event, dict):
            continue
        part = event.get('part')
        for item in (event, part if isinstance(part, dict) else {}):
            session = item.get('sessionID') or item.get('session_id')
            if isinstance(session, str) and session:
                sessions.add(session)
    if not sessions:
        return None
    spec = importlib.util.spec_from_file_location('eval_workflow', ROOT / 'scripts/skalling-workflow.py')
    engine = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(engine)
    return engine.runtime_usage({session: since for session in sessions}, since, until)


def compare(record, baseline):
    previous = next((r for r in baseline if r.get('case') == record['case']
                     and r.get('case_fingerprint') == record.get('case_fingerprint')
                     and r.get('trial', 1) == record.get('trial', 1)), None)
    if previous is None:
        return {'available': False, 'reason': 'No identical case in baseline'}
    result = {'available': True, 'previous_passed': previous.get('passed'),
              'current_passed': record.get('passed'),
              'previous_mode': previous.get('mode', 'team'), 'current_mode': record.get('mode', 'team'),
              'same_requested_model': bool(record.get('model') and record.get('model') == previous.get('model')),
              'controlled': False, 'note': 'Provider/model/load are not controlled; no causal speed claim'}
    for key in ('duration_seconds', 'agent_duration_seconds', 'human_corrections'):
        left, right = previous.get(key), record.get(key)
        result[key + '_delta'] = right - left if left is not None and right is not None else None
    result['token_deltas'] = {}
    for key in ('input', 'output', 'cache_read'):
        left, right = (previous.get('tokens') or {}).get(key), (record.get('tokens') or {}).get(key)
        result['token_deltas'][key] = right - left if left is not None and right is not None else None
    return result


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--output', type=Path, required=True)
    parser.add_argument('--case', choices=[case['id'] for case in CASES])
    parser.add_argument('--timeout', type=int, default=240)
    parser.add_argument('--mode', choices=['team', 'single'], default='team')
    parser.add_argument('--model', help='Same explicit provider/model for both modes')
    parser.add_argument('--repeat', type=int, default=1)
    parser.add_argument('--baseline', type=Path, help='Previous report; comparisons are descriptive, not causal')
    args = parser.parse_args()
    if args.repeat < 1 or args.repeat > 20:
        parser.error('--repeat must be 1..20')
    output = args.output.resolve()
    output.parent.mkdir(parents=True, exist_ok=True)
    work = output.parent / (output.stem + '-fixtures-' + str(time.time_ns()))
    results = []
    baseline = json.loads(args.baseline.read_text()) if args.baseline else []
    for case, trial in ((case, trial) for case in CASES for trial in range(1, args.repeat + 1)):
        if args.case and args.case != case['id']:
            continue
        project = work / (case['id'] + '-' + str(trial))
        record = {'case': case['id'], 'trial': trial, 'mode': args.mode, 'model': args.model,
                  'kind': 'real-agent', 'passed': False,
                  'human_corrections': None, 'tokens': None, 'project': str(project),
                  'harness_version': (ROOT / 'VERSION').read_text().strip(),
                  'case_fingerprint': hashlib.sha256(json.dumps(case, sort_keys=True).encode()).hexdigest()}
        started = time.monotonic()
        since = time.time()
        try:
            baseline_head = prepare(case, project, args.mode)
            log = project.parent / (project.name + '.jsonl')
            with log.open('w') as stream:
                argv = ['opencode', 'run', '--standalone', '--agent',
                        'build' if args.mode == 'single' else 'Alex', '--format', 'json']
                if args.model:
                    argv += ['--model', args.model]
                agent_started = time.monotonic()
                proc = subprocess.Popen([*argv, case['prompt']], cwd=project, stdout=stream,
                                        stderr=subprocess.STDOUT, start_new_session=True)
                try:
                    record['agent_exit_code'] = proc.wait(timeout=args.timeout)
                except subprocess.TimeoutExpired:
                    os.killpg(proc.pid, signal.SIGKILL)
                    proc.wait()
                    record['agent_exit_code'] = 124
                    record['failure_kind'] = 'timeout'
            record['agent_duration_seconds'] = round(time.monotonic() - agent_started, 3)
            behavior = grade(case, project)
            record['behavior_passed'] = behavior.pop('passed')
            record.update(behavior)
            measured = measure(project, case, baseline_head)
            record.update(measured)
            if measured['metrics'].get('tokens_input') is None:
                usage = logged_usage(log, since, time.time())
                if usage is not None:
                    measured['metrics'].update(usage)
            record['tokens'] = {
                'input': measured['metrics'].get('tokens_input'),
                'output': measured['metrics'].get('tokens_output'),
                'cache_read': measured['metrics'].get('tokens_cache_read'),
            }
            record['passed'] = task_passed(record)
            record['log'] = str(log)
        except (OSError, subprocess.SubprocessError) as error:
            record['failure_kind'] = 'runtime-or-setup'
            record['diagnostic'] = str(error)
        record['duration_seconds'] = round(time.monotonic() - started, 3)
        if baseline:
            record['comparison'] = compare(record, baseline)
        results.append(record)
        output.write_text(json.dumps(results, indent=2, ensure_ascii=False) + '\n')
        print(json.dumps(record, ensure_ascii=False), flush=True)
    return 0 if results and all(r['passed'] for r in results) else 1


if __name__ == '__main__':
    sys.exit(main())
