"""Regression replays of the slow/blocked reviews observed in actas3.0.0."""
import importlib.util
import json
import os
from pathlib import Path
import subprocess
import sys
import unittest
from unittest.mock import patch

ROOT = Path(__file__).resolve().parents[1]
PACKAGE = Path(os.environ.get('SKALLING_EFFICIENCY_ROOT', ROOT))
sys.path.insert(0, str(PACKAGE / 'scripts'))
sys.dont_write_bytecode = True
spec = importlib.util.spec_from_file_location('fixtures', ROOT / 'tests/workflow-engine.test.py')
fixtures = importlib.util.module_from_spec(spec)
spec.loader.exec_module(fixtures)
fixtures.ROOT = PACKAGE  # Exercise installed dependencies and DB bootstrap too.


class Efficiency(unittest.TestCase):
    tearDownClass = classmethod(fixtures.Workflow.tearDownClass.__func__)
    call = fixtures.Workflow.call
    start = fixtures.Workflow.start
    configure = fixtures.Workflow.configure

    @classmethod
    def setUpClass(cls):
        # Project bundles use the global installation for DB initialization;
        # their local runtime is still the code under test in every case.
        fixtures.ROOT = Path(os.environ.get('SKALLING_EFFICIENCY_BOOTSTRAP_ROOT', PACKAGE))
        try:
            fixtures.Workflow.setUpClass.__func__(cls)
        finally:
            fixtures.ROOT = PACKAGE

    def setUp(self):
        fixtures.Workflow.setUp(self)
        spec = importlib.util.spec_from_file_location('efficiency_engine', PACKAGE / 'scripts/skalling-workflow.py')
        self.engine = importlib.util.module_from_spec(spec)
        spec.loader.exec_module(self.engine)

    def ready(self, plan=None):
        self.start()
        self.call('teo', 'deliver')
        return self.call('jhon', 'oracle', expected='value one', negative='value two',
                         invariant='integer', refutation='inspect and assert',
                         **({'review_plan': plan} if plan else {}))

    def test_unit_only_never_runs_or_suggests_an_automatic_baseline(self):
        self.configure(unit='touch unexpected-suite')
        started = self.start()
        self.assertNotIn('implementation_probe', self.engine.public_response(started))
        with patch.object(self.engine, 'run_bounded', side_effect=AssertionError('irrelevant suite executed')):
            with self.assertRaisesRegex(ValueError, 'No testing.fast'):
                self.call('teo', 'probe')
            delivered = self.call('teo', 'deliver')
            self.call('jhon', 'oracle', expected='one', negative='two', invariant='integer', refutation='assert')
            with self.assertRaisesRegex(ValueError, 'No testing.fast'):
                self.call('jhon', 'check', configured=True, method='test', criterion='value')
        self.assertEqual(delivered['checks'], [])
        self.assertFalse((self.root / 'unexpected-suite').exists())
        # Previously installed workflows retain their old field, but it must not restore the fallback.
        started['configured_verification'] = ['bash', '-c', 'touch unexpected-suite']
        with self.assertRaisesRegex(ValueError, 'No testing.fast'):
            self.engine.selected_verification(started, {})
        self.assertNotIn('implementation_probe', self.engine.public_response(started))

    def test_explicit_unit_requires_relevance_and_uses_frozen_command(self):
        self.configure(unit='bash tests/check.test.sh')
        self.start()
        self.configure(unit='touch unexpected-suite')
        with self.assertRaisesRegex(ValueError, 'impact_reason'):
            self.call('teo', 'probe', profile='unit')
        result = self.call('teo', 'probe', profile='unit', impact_reason='Shared value contract changes')
        self.assertEqual(result['implementation_checks'][0]['exit_code'], 0)
        self.assertFalse((self.root / 'unexpected-suite').exists())

    def test_invalid_check_can_be_replaced_without_new_delivery(self):
        self.ready(['value stays one'])
        self.call('jhon', 'check', argv=['python3', '-c', 'raise RuntimeError("child_process unavailable")'],
                  criterion='value stays one', method='invalid diagnostic')
        result = self.call('jhon', 'check', inspection={'kind': 'file', 'files': ['app.py']},
                           criterion='value stays one', method='source inspection', replacement_of=0,
                           failure_kind='invalid_check', evidence='Diagnostic used forbidden child_process; inspect the actual source')
        output = json.loads(result['checks'][1]['output'])
        self.assertEqual(output['files'][0]['after'], 'value = 1\n')
        self.assertEqual(result['delivery_number'], 1)
        self.assertEqual(result['checks'][0]['exit_code'], 1)
        self.assertEqual(result['checks'][0]['superseded_by'], 1)
        self.assertIn('child_process', result['checks'][1]['repair_evidence'])
        self.assertIn('inspection_output', self.engine.public_response(result))
        self.assertNotIn('inspection_output', self.engine.public_response(self.call('alex', 'status')))
        self.assertEqual(self.call('jhon', 'approve', evidence='Before/after confirms the declared value')['state'], 'verified')

    def test_invalid_repair_requests_never_execute_and_product_failure_still_blocks(self):
        self.ready()
        self.call('jhon', 'check', argv=['python3', '-c', 'assert False'], method='test', criterion='value')
        base = dict(argv=['bash', 'tests/check.test.sh'], method='test', criterion='value',
                    replacement_of=0, failure_kind='invalid_check', evidence='Wrong diagnostic')
        with patch.object(self.engine, 'run_bounded', side_effect=AssertionError('invalid repair executed')):
            for override in ({'failure_kind': 'product'}, {'evidence': ''}, {'criterion': 'unrelated'},
                             {'replacement_of': 999}, {'retry_of': 0}, {'replacement_of': True}):
                with self.subTest(override=override), self.assertRaises(ValueError):
                    self.call('jhon', 'check', **{**base, **override})
        self.call('jhon', 'check', argv=['bash', 'tests/check.test.sh'], method='test', criterion='different observation',
                  gap='Separate value observation must not clear the unresolved failing assertion')
        with self.assertRaisesRegex(ValueError, 'failing check'):
            self.call('jhon', 'approve', evidence='One green cannot erase the failure')
        self.assertNotIn('superseded_by', self.call('alex', 'status')['checks'][0])

    def test_failed_replacement_does_not_clear_failure_and_repair_chain_is_bounded(self):
        self.ready()
        failed = dict(argv=['python3', '-c', 'assert False'], method='test', criterion='value')
        self.call('jhon', 'check', **failed)
        self.call('jhon', 'check', **failed, replacement_of=0, failure_kind='invalid_check', evidence='Correct assertion harness')
        state = self.call('alex', 'status')
        self.assertNotIn('superseded_by', state['checks'][0])
        result = self.call('jhon', 'check', argv=['bash', 'tests/check.test.sh'], method='test', criterion='value',
                           replacement_of=1, failure_kind='invalid_check', evidence='Use actual project assertion')
        self.assertEqual([c.get('superseded_by') for c in result['checks'][:2]], [2, 2])
        self.call('jhon', 'check', **failed, gap='A new negative case fails after the harness repairs')
        with patch.object(self.engine, 'run_bounded', side_effect=AssertionError('third repair executed')):
            with self.assertRaisesRegex(ValueError, 'budget exhausted'):
                self.call('jhon', 'check', **failed, retry_of=3, failure_kind='flaky', evidence='Transient failure')

    def test_review_plan_stops_redundant_checks_but_allows_a_concrete_gap(self):
        self.ready(['value', 'diff'])
        command = dict(argv=['bash', 'tests/check.test.sh'], method='test', criterion='value')
        self.call('jhon', 'check', **command)
        with self.assertRaisesRegex(ValueError, 'unchecked criteria'):
            self.call('jhon', 'approve', evidence='Only one criterion checked')
        state = self.call('jhon', 'check', inspection={'kind': 'diff'}, method='diff review', criterion='diff')
        self.assertEqual(self.engine.next_action(state)['action'], 'approve')
        with patch.object(self.engine, 'run_bounded', side_effect=AssertionError('redundant check executed')):
            with self.assertRaisesRegex(ValueError, 'gap'):
                self.call('jhon', 'check', **command)
            with self.assertRaisesRegex(ValueError, 'gap'):
                self.call('jhon', 'check', **{**command, 'criterion': 'unplanned'})
        result = self.call('jhon', 'check', **command, gap='Confirm the unchanged integer invariant with the project assertion')
        self.assertIn('gap', result['checks'][-1])
        self.assertEqual(self.call('jhon', 'approve', evidence='Both planned criteria and the gap are covered')['state'], 'verified')

    def test_deterministic_check_reuses_across_resumed_reviewer_sessions(self):
        self.ready(['value'])
        command = dict(argv=['bash', 'tests/check.test.sh'], method='test', criterion='value', reusable=True)
        self.call('jhon', 'check', **command)
        with patch.object(self.engine, 'run_bounded', side_effect=AssertionError('duplicate execution')):
            state = self.engine.operate({'project': str(self.root), 'actor': 'jhon', 'session': 'resumed-jhon',
                                         'action': 'check', 'payload': {'id': 'request', **command}})
        self.assertEqual(state['checks'][-1]['reused_from'], 0)
        self.assertEqual(state['checks'][-1]['session'], 'resumed-jhon')

    def test_inspection_cannot_escape_scope_or_execute_supplied_commands(self):
        state = self.ready()
        for inspection in ({'kind': 'file', 'files': ['../outside']}, {'kind': 'status'},
                           {'kind': 'diff', 'command': 'touch leaked'}, {'kind': 'file', 'files': []}):
            with self.subTest(inspection=inspection), self.assertRaises(ValueError):
                self.call('jhon', 'check', inspection=inspection, method='read', criterion='value')
        with self.assertRaisesRegex(ValueError, 'exactly one'):
            self.call('jhon', 'check', inspection={'kind': 'diff'}, argv=['touch', 'leaked'], method='read', criterion='value')
        (self.root / 'app.py').unlink()
        (self.root / 'app.py').symlink_to('/etc/hosts')
        with self.assertRaisesRegex(ValueError, 'symlink'):
            self.engine.inspection_paths(self.root, state, {'kind': 'file'})
        self.assertFalse((self.root / 'leaked').exists())

    def test_inspection_does_not_silently_truncate_git_baseline(self):
        content = 'value = 1\n' + ''.join(f'# filler {i}\n' for i in range(4000))
        (self.root / 'app.py').write_text(content)
        subprocess.run(['git', 'add', 'app.py'], cwd=self.root, check=True)
        subprocess.run(['git', 'commit', '-qm', 'large baseline'], cwd=self.root, check=True)
        self.start()
        (self.root / 'app.py').write_text(content.replace('value = 1', 'value = 2'))
        self.call('teo', 'deliver')
        self.call('jhon', 'oracle', expected='two', negative='one', invariant='comments', refutation='diff')
        result = self.call('jhon', 'check', inspection={'kind': 'diff', 'files': ['app.py']}, method='diff', criterion='value')
        diff = json.loads(result['checks'][0]['output'])['files'][0]['diff']
        self.assertIn('-value = 1', diff)
        self.assertIn('+value = 2', diff)
        self.assertLess(len(diff), 500)

    def test_actas_home_reorder_finishes_one_delivery_without_global_suite(self):
        # Minimal reproduction of actas3.0.0 f2833ca: the three lines moved
        # below UltimosPosts; the site's existing unit suite was unrelated.
        sectors = '  <SectorsComponent />\n  <RegistrationBannerComponent />\n  <FaqComponent />\n'
        blog = '  <Suspense fallback={<div>Cargando últimas noticias...</div>}>\n    <UltimosPostsComponent />\n  </Suspense>\n'
        page = self.root / 'page.tsx'
        page.write_text('<main>\n' + sectors + blog + '</main>\n')
        subprocess.run(['git', 'add', 'page.tsx'], cwd=self.root, check=True)
        subprocess.run(['git', 'commit', '-qm', 'home baseline'], cwd=self.root, check=True)
        self.configure(unit='touch unexpected-suite')
        self.call('alex', 'start', risk='low', scope='local', files=['page.tsx'],
                  acceptance='Blog appears before sectors; keep all sections', reuse='existing JSX')
        page.write_text('<main>\n' + blog + sectors + '</main>\n')
        self.call('teo', 'deliver')
        self.call('jhon', 'oracle', expected='Blog before sectors', negative='Sectors before blog',
                  invariant='Same sections', refutation='Check source order and diff',
                  review_plan=['section order', 'only section movement'])
        assertion = ('from pathlib import Path; s=Path("page.tsx").read_text(); '
                     'assert s.index("<UltimosPostsComponent") < s.index("<SectorsComponent"); '
                     'assert all(s.count(c)==1 for c in ["<SectorsComponent", "<RegistrationBannerComponent", '
                     '"<FaqComponent", "<UltimosPostsComponent"])')
        self.call('jhon', 'check', argv=['python3', '-c', assertion], method='source order assertion', criterion='section order')
        result = self.call('jhon', 'check', inspection={'kind': 'diff'}, method='diff inspection', criterion='only section movement')
        diff = json.loads(result['checks'][-1]['output'])['files'][0]['diff']
        self.assertEqual(sum(l.startswith('+') and not l.startswith('+++') for l in diff.splitlines()), 3)
        self.assertEqual(sum(l.startswith('-') and not l.startswith('---') for l in diff.splitlines()), 3)
        self.call('jhon', 'approve', evidence='Source order and diff preserve all sections')
        final = self.call('alex', 'complete')
        self.assertEqual(final['state'], 'completed')
        self.assertEqual(final['delivery_number'], 1)
        self.assertEqual(len(final['checks']), 2)
        self.assertFalse(final.get('implementation_checks'))
        self.assertFalse((self.root / 'unexpected-suite').exists())

    def test_native_inspection_reuses_after_age_or_unrelated_changes_without_scanning_workspace(self):
        import time
        self.ready()
        payload = dict(inspection={'kind': 'file', 'files': ['app.py']}, method='source review', criterion='value')
        with patch.object(self.engine, 'evidence_context', side_effect=AssertionError('whole workspace scan')):
            first = self.call('jhon', 'check', **payload)
            (self.root / 'unrelated.txt').write_text('unrelated edit')
            later = time.time() + 3600
            with patch.object(self.engine.time, 'time', return_value=later), \
                 patch.object(self.engine, 'inspect_candidate', side_effect=AssertionError('duplicate Git inspection')):
                reused = self.call('jhon', 'check', **payload)
            self.assertEqual(reused['checks'][-1]['reused_from'], 0)
            self.assertEqual(reused['checks'][-1]['output'], first['checks'][0]['output'])
            (self.root / 'app.py').write_text('value = 2\n')
            with self.assertRaisesRegex(ValueError, 'Candidate changed'):
                self.call('jhon', 'check', **payload)

    def test_luz_has_own_frozen_plan_and_can_share_inspection_without_sharing_approval(self):
        self.start('high', execution_mode='focused')
        self.call('teo', 'deliver')
        self.call('jhon', 'oracle', expected='one', negative='two', invariant='integer', refutation='read source')
        payload = dict(inspection={'kind': 'file', 'files': ['app.py']}, method='inspect', criterion='value')
        self.call('jhon', 'check', **payload)
        with patch.object(self.engine, 'inspect_candidate', side_effect=AssertionError('duplicate inspection')):
            state = self.call('luz', 'check', **{**payload, 'criterion': 'risk'}, review_plan=['risk', 'diff'])
        self.assertEqual(state['checks'][-1]['reused_from'], 0)
        self.assertFalse(state.get('review_verdicts'))
        with self.assertRaisesRegex(ValueError, 'unchecked criteria'):
            self.call('luz', 'approve', evidence='risk covered', findings='No relevant risk found')
        with patch.object(self.engine, 'run_bounded', side_effect=AssertionError('unplanned command')):
            with self.assertRaisesRegex(ValueError, 'gap'):
                self.call('luz', 'check', argv=['true'], criterion='unrelated', method='test')
        self.call('luz', 'check', inspection={'kind': 'diff'}, criterion='diff', method='review')
        self.call('jhon', 'approve', evidence='Value confirmed')
        final = self.call('luz', 'approve', evidence='Risk and diff assessed', findings='No relevant risk found')
        self.assertEqual(final['state'], 'quality_reviewed')

    def test_implicit_plan_cannot_be_omitted_to_add_unrelated_checks(self):
        self.ready()
        state = self.call('jhon', 'check', argv=['bash', 'tests/check.test.sh'], method='assert', criterion='value')
        self.assertEqual(state['oracle']['review_plans']['jhon'], ['value'])
        # Repeating oracle after a plan materializes remains idempotent.
        self.call('jhon', 'oracle', expected='value one', negative='value two', invariant='integer', refutation='inspect and assert')
        with self.assertRaisesRegex(ValueError, 'gap'):
            self.call('jhon', 'check', argv=['true'], method='test', criterion='unrelated')

    def test_luz_starting_parallel_review_does_not_assign_her_plan_to_jhon(self):
        self.start('high', execution_mode='focused')
        self.call('teo', 'deliver')
        oracle = dict(expected='one', negative='two', invariant='integer', refutation='read', review_plan=['risk'])
        self.call('luz', 'oracle', **oracle)
        self.call('luz', 'oracle', **oracle)  # lost-response replay
        self.call('jhon', 'check', inspection={'kind': 'file'}, method='read', criterion='behavior')
        state = self.call('luz', 'check', inspection={'kind': 'file'}, method='read', criterion='risk')
        self.assertEqual(state['oracle']['review_plans'], {'jhon': ['behavior'], 'luz': ['risk']})

    def test_infrastructure_rejection_does_not_consume_another_delivery(self):
        self.ready()
        before = self.call('alex', 'status')
        with self.assertRaisesRegex(ValueError, 'do not reject the product'):
            self.call('jhon', 'reject', failure_kind='infrastructure', evidence='The verifier used a forbidden command')
        after = self.call('alex', 'status')
        for key in ('state', 'delivery_number', 'review_history', 'review_findings'):
            self.assertEqual(after.get(key), before.get(key))

    def test_command_and_cache_validation_times_are_separate(self):
        import time
        self.ready()
        def scan(_root):
            time.sleep(0.03)
            return 'same-inputs'
        with patch.object(self.engine, 'evidence_context', side_effect=scan), \
             patch.object(self.engine, 'run_bounded', return_value=(0, 'value one')):
            state = self.call('jhon', 'check', argv=['bash', 'tests/check.test.sh'], method='test', criterion='value', reusable=True)
        timing = self.engine.public_response(state)['review_timing']
        self.assertGreaterEqual(timing['context_scan_ms'], 50)
        self.assertLess(timing['command_ms'], timing['context_scan_ms'])


if __name__ == '__main__':
    unittest.main()
