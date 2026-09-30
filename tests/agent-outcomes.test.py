"""Test the outcome grader; this is not a claim about any model's capability."""
import importlib.util
import subprocess
from pathlib import Path
import tempfile
import unittest

spec = importlib.util.spec_from_file_location('evals', Path(__file__).parent / 'evals/run.py')
evals = importlib.util.module_from_spec(spec)
spec.loader.exec_module(evals)


class OutcomeGrader(unittest.TestCase):
    def test_success_requires_correct_behavior_and_closed_workflow(self):
        good = {'behavior_passed': True, 'agent_exit_code': 0,
                'diff_scope_passed': True, 'workflow_state': 'completed'}
        self.assertTrue(evals.task_passed(good))
        for state in (None, 'implementation_ready', 'verification_ready', 'verified', 'blocked', 'superseded'):
            with self.subTest(state=state):
                self.assertFalse(evals.task_passed({**good, 'workflow_state': state}))
        for key, value in (('behavior_passed', False), ('agent_exit_code', 124), ('diff_scope_passed', False)):
            with self.subTest(key=key):
                self.assertFalse(evals.task_passed({**good, key: value}))
        self.assertFalse(evals.task_passed({}))

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
            self.assertIn('outside.txt', measured['changed_files'])
            self.assertIsNone(measured['human_corrections'])

    def test_oracles_reject_original_bugs_and_accept_correct_behavior(self):
        fixed = {
            'empty-total': 'def total(values):\n    return sum(values)\n',
            'zero-limit': 'def take(values, limit=None):\n    return values[:] if limit is None else values[:limit]\n',
            'unicode-slug': "def slug(text):\n    return '-'.join(text.lower().split())\n",
        }
        with tempfile.TemporaryDirectory() as folder:
            project = Path(folder)
            for case in evals.CASES:
                with self.subTest(case=case['id']):
                    (project / 'app.py').write_text(case['source'])
                    self.assertFalse(evals.grade(case, project)['passed'])
                    (project / 'app.py').write_text(fixed[case['id']])
                    self.assertTrue(evals.grade(case, project)['passed'])


if __name__ == '__main__':
    unittest.main()
