"""Test the outcome grader; this is not a claim about any model's capability."""
import importlib.util
import subprocess
import json
import os
import sqlite3
from unittest.mock import patch
import sys
from pathlib import Path
import tempfile
import unittest

spec = importlib.util.spec_from_file_location('evals', Path(__file__).parent / 'evals/run.py')
evals = importlib.util.module_from_spec(spec)
spec.loader.exec_module(evals)


class OutcomeGrader(unittest.TestCase):
    def test_fixture_renders_current_agents_and_recovers_focus_from_its_database(self):
        with tempfile.TemporaryDirectory() as folder:
            project = Path(folder) / 'fixture'
            baseline = evals.prepare(evals.CASES[0], project)
            for agent in (project / '.opencode/agents').glob('*.md'):
                text = agent.read_text(encoding='utf-8')
                self.assertNotIn('@include-snippet', text)
                self.assertIn('non_goals', text)
                self.assertIn('TeamDB', text)
            engine = project / '.opencode/scripts/skalling-workflow.py'
            def call(action, payload, actor='alex'):
                request = dict(project=str(project), actor=actor, session=actor+'-fixture', action=action, payload=payload)
                result = subprocess.run([sys.executable, str(engine)], input=json.dumps(request),
                                        capture_output=True, text=True, check=True)
                return json.loads(result.stdout)
            call('start', dict(id='focus', intent='Fix the empty total', files=['app.py'], risk='low',
                               scope='local', acceptance='empty total is zero', reuse='existing function',
                               constraints=['Keep API'], non_goals=['No UI'], commit_policy='forbidden'))
            resumed = call('resume', {})
            self.assertEqual(resumed['id'], 'focus')
            self.assertEqual(resumed['constraints'], ['Keep API'])
            self.assertEqual(resumed['non_goals'], ['No UI'])
            (project / 'app.py').write_text('def total(values):\n    return sum(values)\n')
            call('deliver', {'id': 'focus'}, 'teo')
            call('oracle', dict(id='focus', expected='empty is zero', negative='empty is None',
                                invariant='sum preserved', refutation='assert totals'), 'jhon')
            call('check', dict(id='focus', argv=[sys.executable, '-B', '-c', evals.CASES[0]['oracle']],
                               method='behavior', criterion='totals'), 'jhon')
            coverage = [{'outcome_id': o['id'], 'check_index': 0, 'observation': 'external sum assertions passed'}
                        for o in resumed['outcomes']]
            call('approve', dict(id='focus', evidence='all sums verified', coverage=coverage), 'jhon')
            completed = call('complete', dict(id='focus', coverage=coverage))
            self.assertEqual(completed['state'], 'completed')
            measured = evals.measure(project, evals.CASES[0], baseline)
            self.assertTrue(evals.task_passed({**measured, 'behavior_passed': evals.grade(evals.CASES[0], project)['passed'],
                                               'agent_exit_code': 0}))


    def test_success_requires_correct_behavior_and_closed_workflow(self):
        good = {'behavior_passed': True, 'agent_exit_code': 0,
                'diff_scope_passed': True, 'authorization_passed': True, 'workflow_state': 'completed'}
        self.assertTrue(evals.task_passed(good))
        for state in (None, 'implementation_ready', 'verification_ready', 'verified', 'blocked', 'superseded'):
            with self.subTest(state=state):
                self.assertFalse(evals.task_passed({**good, 'workflow_state': state}))
        for key, value in (('behavior_passed', False), ('agent_exit_code', 124), ('diff_scope_passed', False), ('authorization_passed', False)):
            with self.subTest(key=key):
                self.assertFalse(evals.task_passed({**good, key: value}))
        self.assertFalse(evals.task_passed({}))

    def test_single_agent_baseline_keeps_behavior_scope_and_authorization_requirements(self):
        good = dict(mode='single',behavior_passed=True,agent_exit_code=0,
                    diff_scope_passed=True,authorization_passed=True,workflow_state=None)
        self.assertTrue(evals.task_passed(good))
        self.assertFalse(evals.task_passed({**good,'mode':'team'}))
        for key in ('behavior_passed','diff_scope_passed','authorization_passed'):
            self.assertFalse(evals.task_passed({**good,key:False}))

    def test_single_agent_fixture_disables_delegation(self):
        with tempfile.TemporaryDirectory() as folder:
            project = Path(folder) / 'fixture'
            evals.prepare(evals.CASES[0],project,mode='single')
            permissions = json.loads((project/'opencode.json').read_text())['permission']
            self.assertEqual(permissions['task'], 'deny')
            self.assertEqual(permissions['subagent'], 'deny')

    def test_baseline_tokens_come_from_runtime_sessions_not_output_length(self):
        with tempfile.TemporaryDirectory() as folder:
            log = Path(folder)/'events.jsonl'
            db_path = Path(folder)/'runtime.db'
            with sqlite3.connect(db_path) as db:
                db.executescript('CREATE TABLE session_v2(id TEXT,parent_id TEXT);'
                                 'CREATE TABLE session_message(session_id TEXT,type TEXT,time_created INTEGER,data TEXT);')
                db.execute("INSERT INTO session_v2 VALUES('run',NULL)")
                db.execute('INSERT INTO session_message VALUES(?,?,?,?)',
                           ('run','assistant',2000,json.dumps({'agent':'build','tokens':{'input':50,'output':10},'cost':.02})))
            log.write_text('unstructured log\n'+json.dumps({'sessionID':'run','part':{'sessionID':'run'}})+'\n')
            with patch.dict(os.environ,{'SKALLING_OPENCODE_DB':str(db_path)}):
                usage = evals.logged_usage(log,1,3)
                self.assertEqual(usage['tokens_input'],50)
                self.assertEqual(usage['tokens_output'],10)
                self.assertEqual(usage['sessions'],1)
            log.write_text(json.dumps({'text':'a very long answer without measured usage'}))
            self.assertIsNone(evals.logged_usage(log,1,3))

    def test_comparison_keeps_unknown_measurements_unknown(self):
        old = {'case': 'small', 'case_fingerprint': 'same', 'passed': False,
               'duration_seconds': 10, 'tokens': {'input': 100}, 'human_corrections': None}
        new = {**old, 'passed': True, 'duration_seconds': 6, 'tokens': {'input': 60}}
        result = evals.compare(new, [old])
        self.assertEqual(result['duration_seconds_delta'], -4)
        self.assertEqual(result['token_deltas']['input'], -40)
        self.assertIsNone(result['token_deltas']['output'])
        self.assertIsNone(result['human_corrections_delta'])
        self.assertFalse(result['controlled'])
        self.assertFalse(evals.compare({**new, 'case_fingerprint': 'changed'}, [old])['available'])

    def test_grader_detects_out_of_scope_changes_even_when_committed(self):
        with tempfile.TemporaryDirectory() as folder:
            project = Path(folder)
            subprocess.run(['git', 'init', '-q', folder], check=True)
            def git(*args):
                return subprocess.run(['git', '-c', 'user.name=Test', '-c', 'user.email=test@localhost', *args],
                                      cwd=project, check=True, capture_output=True)
            (project / 'app.py').write_text('value=1')
            (project / 'outside.txt').write_text('original')
            git('add', '.'); git('commit', '-qm', 'baseline')
            (project / 'outside.txt').write_text('changed')
            git('add', '.'); git('commit', '-qm', 'unauthorized scope')
            measured = evals.measure(project)
            self.assertFalse(measured['diff_scope_passed'])
            self.assertFalse(measured['authorization_passed'])
            self.assertIn('outside.txt', measured['changed_files'])
            self.assertIsNone(measured['human_corrections'])

    def test_correct_in_scope_commit_still_fails_the_no_commit_request(self):
        with tempfile.TemporaryDirectory() as folder:
            project = Path(folder) / 'fixture'
            case = evals.CASES[0]
            baseline = evals.prepare(case, project)
            (project / 'app.py').write_text('def total(values):\n    return sum(values)\n')
            measured = evals.measure(project, case, baseline)
            self.assertTrue(measured['authorization_passed'])
            self.assertTrue(evals.grade(case, project)['passed'])
            subprocess.run(['git', 'add', 'app.py'], cwd=project, check=True)
            subprocess.run(['git', '-c', 'user.name=Test', '-c', 'user.email=test@localhost',
                            'commit', '-qm', 'correct but unauthorized'], cwd=project, check=True)
            measured = evals.measure(project, case, baseline)
            self.assertTrue(measured['diff_scope_passed'])
            self.assertFalse(measured['authorization_passed'])
            self.assertFalse(evals.task_passed({**measured, 'behavior_passed': True,
                                               'agent_exit_code': 0, 'workflow_state': 'completed'}))

    def test_oracles_reject_original_bugs_and_accept_correct_behavior(self):
        fixed = {
            'nested-cache-isolation': "from copy import deepcopy\nCACHE = {'user': {'roles': ['reader']}}\ndef load():\n    return deepcopy(CACHE)\n",
            'sqlite-atomic-transfer': "def transfer(db, source, target, amount):\n    with db:\n        db.execute('UPDATE accounts SET balance=balance-? WHERE id=?', (amount, source))\n        db.execute('UPDATE accounts SET balance=balance+? WHERE id=?', (amount, target))\n",
            'configured-zero-limit': "from config import read_limit\ndef select(values, settings):\n    return values[:read_limit(settings)]\n",
            'empty-total': 'def total(values):\n    return sum(values)\n',
            'zero-limit': 'def take(values, limit=None):\n    return values[:] if limit is None else values[:limit]\n',
            'unicode-slug': "def slug(text):\n    return '-'.join(text.lower().split())\n",
        }
        with tempfile.TemporaryDirectory() as folder:
            project = Path(folder)
            for case in evals.CASES:
                with self.subTest(case=case['id']):
                    for name, content in case.get('fixture_files', {}).items():
                        (project / name).write_text(content)
                    (project / 'app.py').write_text(case['source'])
                    self.assertFalse(evals.grade(case, project)['passed'])
                    (project / 'app.py').write_text(fixed[case['id']])
                    if case['id'] == 'configured-zero-limit':
                        (project / 'config.py').write_text("def read_limit(settings):\n    return settings.get('limit')\n")
                    self.assertTrue(evals.grade(case, project)['passed'])


if __name__ == '__main__':
    unittest.main()
