import importlib.util
from pathlib import Path
import tempfile
import threading
import time
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
        subprocess.run(['git', '-C', str(self.root), 'config', 'user.email', 'test@example.com'], check=True)
        subprocess.run(['git', '-C', str(self.root), 'config', 'user.name', 'Test'], check=True)
        subprocess.run(['git', '-C', str(self.root), 'add', '-A'], check=True)
        subprocess.run(['git', '-C', str(self.root), 'commit', '-q', '-m', 'init'], check=True)

    def call(self, actor, action, **payload):
        return self.engine.operate({'project': str(self.root), 'actor': actor, 'session': actor+'-session',
                                    'action': action, 'payload': {'id': 'request', **payload}})

    def start(self, risk='low'):
        return self.call('alex', 'start', risk=risk, files=['app.py', 'tests/check.test.sh'],
                         acceptance='value remains one', scope='local', decision='none')

    def verify(self):
        self.call('teo', 'deliver')
        self.call('jhon', 'oracle', expected='value one', negative='value two', invariant='integer', refutation='test value')
        self.call('jhon', 'check', argv=['bash', 'tests/check.test.sh'], method='falsification', criterion='value stays 1')
        return self.call('jhon', 'approve', evidence='falsification check covers the declared acceptance criterion')

    def test_fast_route_requires_independent_executed_verification(self):
        self.assertEqual(self.start()['state'], 'implementation_ready')
        with self.assertRaises(ValueError): self.call('teo', 'complete')
        self.call('teo', 'deliver')
        with self.assertRaises(ValueError): self.call('teo', 'check', argv=['bash', 'tests/check.test.sh'])
        with self.assertRaises(ValueError): self.call('jhon', 'check', argv=['bash', 'tests/check.test.sh'])
        self.call('jhon', 'oracle', expected='one', negative='two', invariant='integer', refutation='test')
        checked = self.call('jhon', 'check', argv=['bash', 'tests/check.test.sh'], method='falsification', criterion='value stays 1')
        self.assertEqual(checked['state'], 'verification_ready', "a check must not approve by itself")
        with self.assertRaises(ValueError): self.call('alex', 'complete')
        self.assertEqual(self.call('jhon', 'approve', evidence='falsification covers the criterion')['state'], 'verified')
        self.assertEqual(self.call('alex', 'complete')['state'], 'completed')

    def test_running_true_records_evidence_but_never_approves(self):
        # The exploit this locks in: `true` always exits 0, so if a check
        # could approve by itself, "verification" would be theater. Now
        # check() only records the observation; approve() is a distinct,
        # deliberate act that a bare `true` run does not by itself unlock
        # more than a real one would -- the gate is the separate approve
        # step and the "all relevant checks pass" requirement, not this
        # command's specific content.
        self.start()
        self.call('teo', 'deliver')
        self.call('jhon', 'oracle', expected='one', negative='two', invariant='integer', refutation='test')
        checked = self.call('jhon', 'check', argv=['true'], method='falsification', criterion='value stays 1')
        self.assertEqual(checked['state'], 'verification_ready')
        with self.assertRaises(ValueError):
            self.call('alex', 'complete')

    def test_check_requires_a_named_criterion(self):
        self.start()
        self.call('teo', 'deliver')
        self.call('jhon', 'oracle', expected='one', negative='two', invariant='integer', refutation='test')
        with self.assertRaises(ValueError):
            self.call('jhon', 'check', argv=['bash', 'tests/check.test.sh'], method='falsification')

    def test_approve_requires_a_recorded_check_and_evidence(self):
        self.start()
        self.call('teo', 'deliver')
        self.call('jhon', 'oracle', expected='one', negative='two', invariant='integer', refutation='test')
        with self.assertRaises(ValueError):
            self.call('jhon', 'approve', evidence='nothing was actually run')
        self.call('jhon', 'check', argv=['bash', 'tests/check.test.sh'], method='falsification', criterion='value stays 1')
        with self.assertRaises(ValueError):
            self.call('jhon', 'approve', evidence='')

    def test_a_later_passing_check_does_not_erase_an_earlier_failure(self):
        self.start()
        self.call('teo', 'deliver')
        self.call('jhon', 'oracle', expected='one', negative='two', invariant='integer', refutation='test')
        self.call('jhon', 'check', argv=['false'], method='falsification', criterion='invariant holds')
        self.call('jhon', 'check', argv=['bash', 'tests/check.test.sh'], method='falsification', criterion='value stays 1')
        with self.assertRaises(ValueError):
            self.call('jhon', 'approve', evidence='the second check passed')

    def test_jhon_can_record_several_checks_before_approving(self):
        self.start()
        self.call('teo', 'deliver')
        self.call('jhon', 'oracle', expected='one', negative='two', invariant='integer', refutation='test')
        self.call('jhon', 'check', argv=['bash', 'tests/check.test.sh'], method='falsification', criterion='value stays 1')
        self.call('jhon', 'check', argv=['true'], method='falsification', criterion='no crash on empty input')
        self.assertEqual(self.call('jhon', 'approve', evidence='both criteria covered')['state'], 'verified')

    def test_high_route_cannot_skip_luz_or_documentation(self):
        self.start('high')
        self.call('pol', 'clarify', evidence='approved scope')
        self.call('sol', 'plan', evidence='design and rollback')
        self.call('sol', 'ready', evidence='dependencies ready')
        self.verify()
        with self.assertRaises(ValueError): self.call('alex', 'complete')
        with self.assertRaises(ValueError): self.call('pau', 'document', evidence='notes')
        self.call('luz', 'check', argv=['bash', 'tests/check.test.sh'], method='trust-boundaries', criterion='no privilege escalation')
        with self.assertRaises(ValueError):
            self.call('luz', 'approve', evidence='reviewed')
        self.call('luz', 'approve', evidence='reviewed trust boundaries and scope',
                  findings='No secrets, no privilege escalation; scope stays within declared files')
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
        result = self.call('jhon', 'check', argv=['bash', 'tests/check.test.sh'], method='falsification', criterion='value stays 1')
        self.assertEqual(result['state'], 'verification_ready')
        self.assertEqual(result['verification']['exit_code'], 1)
        with self.assertRaises(ValueError):
            self.call('jhon', 'approve', evidence='observed a failure but approving anyway')
        self.assertEqual(self.call('jhon', 'reject', evidence='expected one, observed two')['state'], 'implementation_ready')

    def test_scope_cannot_escape_project(self):
        with self.assertRaises(ValueError):
            self.call('alex', 'start', risk='low', files=['../outside'], acceptance='x', scope='local', decision='none')

    def test_undeclared_change_is_scope_creep_until_rescoped(self):
        self.start()
        (self.root / 'extra.py').write_text('bonus = 1\n')
        with self.assertRaises(ValueError):
            self.call('teo', 'deliver')
        self.call('teo', 'rescope', files=['extra.py'], evidence='needed a shared helper module')
        self.assertEqual(self.call('teo', 'deliver')['state'], 'verification_ready')

    def test_rescope_requires_evidence_and_new_files(self):
        self.start()
        with self.assertRaises(ValueError):
            self.call('teo', 'rescope', files=['app.py'], evidence='no new file, same as declared')
        with self.assertRaises(ValueError):
            self.call('teo', 'rescope', files=['extra.py'], evidence='')

    def test_delivery_identity_classifies_added_modified_deleted(self):
        (self.root / 'tests/old.py').write_text('legacy = 1\n')
        subprocess.run(['git', '-C', str(self.root), 'add', '-A'], check=True)
        subprocess.run(['git', '-C', str(self.root), 'commit', '-q', '-m', 'add old.py'], check=True)
        self.call('alex', 'start', risk='low', files=['app.py', 'tests/check.test.sh', 'tests/old.py', 'extra.py'],
                  acceptance='x', scope='local', decision='none')
        (self.root / 'app.py').write_text('value = 2\n')  # modified
        (self.root / 'extra.py').write_text('bonus = 1\n')  # added (new to git)
        (self.root / 'tests/old.py').unlink()  # deleted
        result = self.call('teo', 'deliver')
        delivery = result['delivery']
        self.assertEqual(delivery['added'], ['extra.py'])
        self.assertEqual(delivery['modified'], ['app.py'])
        self.assertEqual(delivery['deleted'], ['tests/old.py'])
        self.assertNotIn('tests/check.test.sh', delivery['added'] + delivery['modified'] + delivery['deleted'])
        self.assertIsNotNone(delivery['base_head'])
        self.assertEqual(delivery['delivery_number'], 1)

    def test_delivery_number_increments_on_redelivery(self):
        self.start()
        self.call('teo', 'deliver')
        self.assertEqual(self.call('jhon', 'reject', evidence='needs another pass')['delivery']['delivery_number'], 1)
        second = self.call('teo', 'deliver')
        self.assertEqual(second['delivery']['delivery_number'], 2)

    def test_rescope_into_a_new_area_escalates_risk(self):
        (self.root / 'src').mkdir()
        (self.root / 'src/other.py').write_text('x = 1\n')
        subprocess.run(['git', '-C', str(self.root), 'add', '-A'], check=True)
        subprocess.run(['git', '-C', str(self.root), 'commit', '-q', '-m', 'add src'], check=True)
        result = self.start()
        self.assertEqual(result['risk'], 'low')
        rescoped = self.call('teo', 'rescope', files=['src/other.py'], evidence='needed a shared helper in src/')
        self.assertEqual(rescoped['risk'], 'medium')
        self.assertEqual(rescoped['route'], 'INLINE')

    def test_slow_verification_does_not_hold_the_write_lock(self):
        # A 'check' running a slow command must not block other agent_workflows
        # writers behind it (the original bug: BEGIN IMMEDIATE held across
        # subprocess.run, other connections only wait 10s).
        self.start()
        self.call('teo', 'deliver')
        self.call('jhon', 'oracle', expected='one', negative='two', invariant='integer', refutation='test')

        results = {}

        def slow_check():
            start = time.monotonic()
            self.call('jhon', 'check', argv=['bash', '-c', 'sleep 1; exit 0'], method='falsification', criterion='value stays 1')
            results['check_duration'] = time.monotonic() - start

        thread = threading.Thread(target=slow_check)
        thread.start()
        time.sleep(0.2)  # let the slow check pass its pre-checks and release the lock

        concurrent_start = time.monotonic()
        self.engine.operate({'project': str(self.root), 'actor': 'alex', 'session': 'other-session',
                             'action': 'start', 'payload': {'id': 'other-request', 'risk': 'low',
                             'files': ['app.py'], 'acceptance': 'x', 'scope': 'local', 'decision': 'none'}})
        concurrent_duration = time.monotonic() - concurrent_start
        thread.join()

        self.assertLess(concurrent_duration, 0.5, 'a concurrent write waited behind the held lock')


if __name__ == '__main__': unittest.main()
