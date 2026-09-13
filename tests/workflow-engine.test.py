import importlib.util
from pathlib import Path
import tempfile
import unittest
import subprocess

ROOT = Path(__file__).resolve().parents[1]


class Workflow(unittest.TestCase):
    def setUp(self):
        spec = importlib.util.spec_from_file_location('workflow', ROOT / 'scripts/skalling-workflow.py')
        self.engine = importlib.util.module_from_spec(spec)
        spec.loader.exec_module(self.engine)
        self.tmp = tempfile.TemporaryDirectory()
        self.addCleanup(self.tmp.cleanup)
        self.root = Path(self.tmp.name)
        (self.root / '.opencode/context').mkdir(parents=True)
        (self.root / 'app.py').write_text('value = 1\n')
        (self.root / 'tests').mkdir()
        (self.root / 'tests/check.test.sh').write_text('test "$(cat app.py)" = "value = 1"\n')
        subprocess.run(['git', 'init', '-q', str(self.root)], check=True)

    def call(self, actor, action, **payload):
        return self.engine.operate({'project': str(self.root), 'actor': actor, 'session': actor+'-session',
                                    'action': action, 'payload': {'id': 'request', **payload}})

    def start(self, risk='low'):
        return self.call('alex', 'start', risk=risk, files=['app.py', 'tests/check.test.sh'],
                         acceptance='value remains one', scope='local', decision='none')

    def verify(self):
        self.call('teo', 'deliver')
        self.call('jhon', 'oracle', expected='value one', negative='value two', invariant='integer', refutation='test value')
        return self.call('jhon', 'check', argv=['bash', 'tests/check.test.sh'], method='falsification')

    def test_fast_route_requires_independent_executed_verification(self):
        self.assertEqual(self.start()['state'], 'implementation_ready')
        with self.assertRaises(ValueError): self.call('teo', 'complete')
        self.call('teo', 'deliver')
        with self.assertRaises(ValueError): self.call('teo', 'check', argv=['bash', 'tests/check.test.sh'])
        with self.assertRaises(ValueError): self.call('jhon', 'check', argv=['bash', 'tests/check.test.sh'])
        self.call('jhon', 'oracle', expected='one', negative='two', invariant='integer', refutation='test')
        self.assertEqual(self.call('jhon', 'check', argv=['bash', 'tests/check.test.sh'], method='falsification')['state'], 'verified')
        self.assertEqual(self.call('alex', 'complete')['state'], 'completed')

    def test_high_route_cannot_skip_luz_or_documentation(self):
        self.start('high')
        self.call('pol', 'clarify', evidence='approved scope')
        self.call('sol', 'plan', evidence='design and rollback')
        self.call('sol', 'ready', evidence='dependencies ready')
        self.verify()
        with self.assertRaises(ValueError): self.call('alex', 'complete')
        with self.assertRaises(ValueError): self.call('pau', 'document', evidence='notes')
        self.call('luz', 'check', argv=['bash', 'tests/check.test.sh'], method='trust-boundaries')
        self.call('pau', 'document', evidence='decision and limits')
        self.assertEqual(self.call('alex', 'complete')['state'], 'completed')

    def test_changed_candidate_invalidates_verification(self):
        self.start()
        self.verify()
        (self.root / 'app.py').write_text('value = 2\n')
        with self.assertRaises(ValueError): self.call('alex', 'complete')

    def test_failed_test_never_approves_and_can_return_to_teo(self):
        self.start()
        (self.root / 'app.py').write_text('value = 2\n')
        self.call('teo', 'deliver')
        self.call('jhon', 'oracle', expected='one', negative='two', invariant='integer', refutation='test')
        result = self.call('jhon', 'check', argv=['bash', 'tests/check.test.sh'], method='falsification')
        self.assertEqual(result['state'], 'verification_ready')
        self.assertEqual(result['verification']['exit_code'], 1)
        self.assertEqual(self.call('jhon', 'reject', evidence='expected one, observed two')['state'], 'implementation_ready')

    def test_scope_cannot_escape_project(self):
        with self.assertRaises(ValueError):
            self.call('alex', 'start', risk='low', files=['../outside'], acceptance='x', scope='local', decision='none')


if __name__ == '__main__': unittest.main()
