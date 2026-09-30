#!/usr/bin/env python3
"""Run real agent tasks, graded by an external oracle, never by its final prose.

Example: python3 tests/evals/run.py --output /path/results.json --case empty-total
Requires an installed OpenCode runtime/provider. Model selection is inherited.
Fixtures and logs remain beside the report. No passing result is invented when
runtime setup, permissions or provider access fail. Not part of ordinary CI.
"""
import argparse
import hashlib
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
    """A correct patch left in an unfinished workflow is not a delivered task."""
    return (record.get('behavior_passed') is True
            and record.get('agent_exit_code') == 0
            and record.get('diff_scope_passed') is True
            and record.get('workflow_state') == 'completed')


def measure(project):
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
    changed_files = sorted({line[3:] for line in changed.stdout.splitlines() if len(line) > 3}
                           | set(diff.stdout.splitlines()))
    return {
        'metrics': metrics,
        'workflow_state': workflow.get('state'),
        'workflow_deliveries': workflow.get('delivery_number'),
        'workflow_last_rejection': workflow.get('last_rejection'),
        'changed_files': changed_files,
        'human_corrections': workflow.get('human_corrections'),
        'user_acceptance': workflow.get('user_acceptance'),
        'outcome_coverage': workflow.get('coverage'),
        'diff_scope_passed': changed.returncode == 0 and diff.returncode == 0 and set(changed_files) <= {'app.py'},
    }


def prepare(case, project):
    project.mkdir(parents=True)
    (project / 'app.py').write_text(case['source'])
    (project / 'README.md').write_text('# Evaluation fixture\nSmall Python utility; preserve its public API.\n')
    (project / '.gitignore').write_text('.opencode/\n__pycache__/\nopencode.json\ndb/teamdb/\n')
    subprocess.run(['git', 'init', '-q'], cwd=project, check=True)
    subprocess.run(['git', '-c', 'user.name=Eval', '-c', 'user.email=eval@localhost',
                    'add', 'app.py', 'README.md', '.gitignore'], cwd=project, check=True)
    subprocess.run(['git', '-c', 'user.name=Eval', '-c', 'user.email=eval@localhost',
                    'commit', '-qm', 'fixture baseline'], cwd=project, check=True)
    config = project / '.opencode'
    config.mkdir()
    # Use the current checkout's prompts and plugins, not stale installed copies.
    shutil.copytree(ROOT / '.opencode/agents', config / 'agents')
    shutil.copytree(ROOT / 'plugins', config / 'plugins')
    shutil.copytree(ROOT / 'scripts', config / 'scripts', ignore=shutil.ignore_patterns('__pycache__'))
    shutil.copytree(ROOT / 'sql', config / 'sql')
    shutil.copyfile(ROOT / 'templates/opencode.json', project / 'opencode.json')
    subprocess.run(['bash', str(ROOT / 'scripts/teamdb-init.sh'), str(project)], check=True, capture_output=True)
    # A real context record via the normal helper; no agent claims fabricated.
    subprocess.run(['bash', str(ROOT / 'scripts/teamdb-memory.sh'), '--project', str(project),
                    'concept', 'project-summary', 'Fixture', 'Python utility with an existing app.py API'],
                   check=True, capture_output=True)
    import sqlite3
    with sqlite3.connect(config / 'context/team.db') as db:
        db.execute("INSERT OR REPLACE INTO schema_meta(key,value) VALUES('project_readiness','initialized')")
    (config / 'project.yaml').write_text('testing:\n  unit:\n    available: true\n    command: "python3 -B -m py_compile app.py"\n')
    (project / '.gitignore').write_text('.opencode/\n__pycache__/\nopencode.json\ndb/teamdb/\n')


def compare(record, baseline):
    previous = next((r for r in baseline if r.get('case') == record['case']
                     and r.get('case_fingerprint') == record.get('case_fingerprint')), None)
    if previous is None:
        return {'available': False, 'reason': 'No identical case in baseline'}
    result = {'available': True, 'previous_passed': previous.get('passed'),
              'current_passed': record.get('passed'),
              'controlled': False, 'note': 'Provider/model/load are not controlled; no causal speed claim'}
    for key in ('duration_seconds', 'human_corrections'):
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
    parser.add_argument('--baseline', type=Path, help='Previous report; comparisons are descriptive, not causal')
    args = parser.parse_args()
    output = args.output.resolve()
    output.parent.mkdir(parents=True, exist_ok=True)
    work = output.parent / (output.stem + '-fixtures-' + str(time.time_ns()))
    results = []
    baseline = json.loads(args.baseline.read_text()) if args.baseline else []
    for case in CASES:
        if args.case and args.case != case['id']:
            continue
        project = work / case['id']
        record = {'case': case['id'], 'kind': 'real-agent', 'passed': False,
                  'human_corrections': None, 'tokens': None, 'project': str(project),
                  'harness_version': (ROOT / 'VERSION').read_text().strip(),
                  'case_fingerprint': hashlib.sha256(json.dumps(case, sort_keys=True).encode()).hexdigest()}
        started = time.monotonic()
        try:
            prepare(case, project)
            log = project.parent / (case['id'] + '.jsonl')
            with log.open('w') as stream:
                proc = subprocess.Popen(['opencode', 'run', '--standalone', '--agent', 'Alex', '--format', 'json',
                                         case['prompt']], cwd=project, stdout=stream, stderr=subprocess.STDOUT,
                                        start_new_session=True)
                try:
                    record['agent_exit_code'] = proc.wait(timeout=args.timeout)
                except subprocess.TimeoutExpired:
                    os.killpg(proc.pid, signal.SIGKILL)
                    proc.wait()
                    record['agent_exit_code'] = 124
                    record['failure_kind'] = 'timeout'
            behavior = grade(case, project)
            record['behavior_passed'] = behavior.pop('passed')
            record.update(behavior)
            measured = measure(project)
            record.update(measured)
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
