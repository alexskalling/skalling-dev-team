"""Regression: one request, complete review findings, one correction, real commit."""
import importlib.util
from pathlib import Path
import sys
import unittest
import threading
import json
import sqlite3
from unittest.mock import patch

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT / 'scripts'))
spec = importlib.util.spec_from_file_location('workflow_tests', ROOT / 'tests/workflow-engine.test.py')
base = importlib.util.module_from_spec(spec)
spec.loader.exec_module(base)


class ReviewCycle(base.Workflow):
    def test_resolution_error_explains_exact_ids_without_consuming_delivery(self):
        self.start()
        self.call('teo', 'deliver')
        state = self.call('jhon', 'reject', evidence='wrong value', findings=[
            {'id': 'value', 'problem': 'value is two', 'expected': 'value is one'}])
        with self.assertRaises(ValueError) as error:
            self.call('teo', 'deliver', resolutions=[
                {'finding_id': 'o1-product-result', 'change': 'Implemented feature'}])
        message = str(error.exception)
        self.assertIn('jhon:value', message)
        self.assertIn('o1-product-result', message)
        self.assertIn('value is two', message)
        self.assertIn('no son outcomes', message)
        after = self.call('alex', 'status')
        for field in ('delivery_number', 'rejection_count', 'review_findings', 'checks'):
            self.assertEqual(after[field], state[field])
        delivered = self.call('teo', 'deliver', resolutions=[
            {'finding_id': 'jhon:value', 'change': 'Fixed app.py value'}])
        self.assertEqual(delivered['delivery_number'], 2)

    def test_stringified_findings_keep_individual_ids_and_criteria(self):
        self.start()
        self.call('teo', 'deliver')
        findings = [{'id': 'jhon:pr-array', 'problem': 'Native array discarded',
                     'expected': 'Preserve native array'},
                    {'id': 'status-array', 'problem': 'Pending status discarded',
                     'expected': 'Block pending'}]
        state = self.call('jhon', 'reject', evidence='API fixtures differ', findings=json.dumps(findings))
        self.assertEqual([f['id'] for f in state['review_findings']], ['jhon:pr-array', 'jhon:status-array'])
        self.assertEqual([f['expected'] for f in state['review_findings']], [f['expected'] for f in findings])

    def test_duplicate_resolution_is_actionable_and_does_not_mutate_findings(self):
        self.start()
        self.call('teo', 'deliver')
        state = self.call('jhon', 'reject', evidence='wrong value')
        fid = state['review_findings'][0]['id']
        with self.assertRaises(ValueError) as error:
            self.call('teo', 'deliver', resolutions=[{'finding_id': fid, 'change': 'Fix'}] * 2)
        self.assertIn('duplicados', str(error.exception))
        self.assertIn(fid, str(error.exception))
        self.assertEqual(self.call('alex', 'status')['review_findings'], state['review_findings'])

    def test_batch_reviews_then_single_correction_and_commit(self):
        self.call('alex', 'start', risk='high', scope='cross-cutting', sensitive=True,
                  planning_required=False, files=['app.py'], acceptance='value is one', reuse='app')
        self.assertEqual(self.call('alex', 'status')['state'], 'implementation_ready')
        (self.root / 'app.py').write_text('value = 2\n')
        self.call('teo', 'deliver')
        self.call('jhon', 'oracle', expected='one', negative='two', invariant='int', refutation='assert value')
        jhon = self.call('jhon', 'reject', evidence='wrong value',
                         findings=[{'id': 'value', 'problem': 'value is two', 'expected': 'value is one'}])
        self.assertEqual(jhon['state'], 'verification_ready', 'Collect Luz findings before editing again')
        with self.assertRaises(ValueError): self.call('teo', 'deliver')
        rejected = self.call('luz', 'reject', evidence='missing comment',
                             findings=[{'id': 'comment', 'problem': 'missing contract comment', 'expected': 'contract comment'}])
        self.assertEqual(rejected['state'], 'implementation_ready')
        self.assertEqual(len(rejected['review_findings']), 2)
        with self.assertRaisesRegex(ValueError, 'resolutions'):
            self.call('teo', 'deliver')
        (self.root / 'app.py').write_text('# contract\nvalue = 1\n')
        delivered = self.call('teo', 'deliver', resolutions=[
            {'finding_id': f['id'], 'change': 'Corrected value and contract comment in app.py'}
            for f in rejected['review_findings']])
        self.assertIsNotNone(delivered['oracle'], 'Do not reinvent unchanged acceptance criteria')
        self.assertEqual(delivered['delivery_number'], 2)
        self.call('luz', 'check', argv=['python3', '-B', '-c', 'from app import value; assert value == 1'],
                  method='risk check', criterion='one', reusable=True)
        self.call('luz', 'approve', evidence='All findings fixed', findings='Risk checked')
        self.call('jhon', 'check', argv=['python3', '-B', '-c', 'from app import value; assert value == 1'],
                  method='behavior', criterion='one')
        approved = self.call('jhon', 'approve', evidence='Both outcomes verified')
        self.assertEqual(approved['state'], 'quality_reviewed')
        self.assertEqual(self.engine.next_action(approved)['action'], 'commit')
        self.assertTrue(all(f['status'] == 'resolved' for f in approved['review_findings']))
        with self.assertRaisesRegex(ValueError, 'Falta commit local'):
            self.call('alex', 'complete')
        committed = self.call('luz', 'commit', message='fix: value and contract')
        self.assertTrue(committed['local_commit_result']['created'])
        self.assertEqual(self.engine.next_action(committed)['action'], 'complete')
        self.assertEqual(self.call('alex', 'complete')['state'], 'completed')

    def test_start_rejects_misspelled_outcomes_before_creating_work(self):
        with self.assertRaisesRegex(ValueError, 'outcomes'):
            self.call('alex', 'start', risk='low', scope='local', files=['app.py'],
                      acceptance='one', reuse='app', outcome_definitions={'id': 'one', 'expected': 'one'})

    def test_new_id_cannot_restart_active_work_on_same_files(self):
        self.start()
        with self.assertRaisesRegex(ValueError, 'request'):
            self.call('alex', 'start', id='other', risk='low', scope='local', files=['app.py'],
                      acceptance='one', reuse='app')

    def test_correction_retains_diagnostics_without_accepting_stale_checks(self):
        self.start()
        self.call('teo', 'deliver')
        self.call('jhon', 'oracle', expected='one', negative='two', invariant='int', refutation='assert')
        self.call('jhon', 'check', argv=['python3', '-c', 'print("proof before correction")'],
                  method='diagnostic', criterion='diagnostic only')
        rejected = self.call('jhon', 'reject', evidence='value must change')
        self.assertIn('proof before correction', rejected['review_history'][0]['checks'][0]['output'])
        (self.root / 'app.py').write_text('value = 2\n')
        delivered = self.call('teo', 'deliver', resolutions=[
            {'finding_id': f['id'], 'change': 'Changed value in app.py'} for f in rejected['review_findings']])
        self.assertEqual(delivered['checks'], [])
        self.assertEqual(len(delivered['review_history']), 1)
        self.assertEqual(delivered['review_findings'][0]['status'], 'addressed')
        with self.assertRaises(ValueError): self.call('jhon', 'approve', evidence='old proof')

    def test_supersedes_preserves_exhausted_budget(self):
        state = self.start()
        for _ in range(3):
            self.call('teo', 'deliver', resolutions=[{'finding_id': f['id'], 'change': 'Attempt fix'}
                                                    for f in state.get('review_findings', [])])
            state = self.call('jhon', 'reject', evidence='still broken')
        with self.assertRaisesRegex(ValueError, 'Presupuesto'):
            self.call('alex', 'start', id='retry', supersedes='request', risk='low', scope='local',
                      files=['app.py'], acceptance='one', reuse='app')
        self.assertEqual(self.call('alex', 'status')['state'], 'blocked')

    def test_parallel_checks_do_not_lose_evidence_when_reviewers_finish_together(self):
        self.call('alex', 'start', risk='high', scope='local', execution_mode='direct',
                  files=['app.py'], acceptance='one', reuse='app')
        self.call('teo', 'deliver')
        self.call('jhon', 'oracle', expected='one', negative='two', invariant='int', refutation='assert')
        barrier, errors = threading.Barrier(2), []
        def command(*args):
            barrier.wait(timeout=3)
            return 0, 'observed one'
        def review(actor):
            try:
                self.call(actor, 'check', argv=['python3', '-c', 'print(1)'], method='assertion', criterion='one')
            except Exception as error: errors.append(error)
        with patch.object(self.engine, 'run_bounded', side_effect=command):
            threads = [threading.Thread(target=review, args=(role,)) for role in ('jhon', 'luz')]
            for thread in threads: thread.start()
            for thread in threads: thread.join(timeout=5)
        self.assertEqual(errors, [])
        self.assertEqual({c['agent'] for c in self.call('alex', 'status')['checks']}, {'jhon', 'luz'})

    def test_resume_legacy_rejection_keeps_identity_budget_and_pending_diagnostic(self):
        self.start()
        self.call('teo', 'deliver')
        state = self.call('jhon', 'reject', evidence='wrong output')
        for key in ('review_protocol', 'review_findings', 'review_history', 'review_verdicts'):
            state.pop(key, None)
        with sqlite3.connect(self.db_path) as db:
            db.execute('UPDATE agent_workflows SET body=? WHERE id=?', (json.dumps(state), state['id']))
        resumed = self.call('alex', 'status')
        self.assertEqual(resumed['review_protocol'], 2)
        self.assertEqual(resumed['delivery_number'], 1)
        self.assertEqual(resumed['rejection_count'], 1)
        self.assertEqual(resumed['review_findings'][0]['problem'], 'wrong output')
        with self.assertRaisesRegex(ValueError, 'resolutions'): self.call('teo', 'deliver')

    def test_reopening_after_commit_never_reports_the_old_sha_as_the_new_commit(self):
        self.start()
        test = self.root / 'tests/check.test.sh'
        test.write_text(test.read_text() + '# first correction\n')
        self.verify()
        first = self.call('jhon', 'commit', message='fix: first candidate')['local_commit_result']['sha']
        rejected = self.call('jhon', 'reject', evidence='needs a second correction')
        self.assertNotIn('local_commit_result', rejected)
        self.assertEqual(rejected['local_commit_history'][0]['sha'], first)
        test.write_text(test.read_text() + '# second correction\n')
        self.call('teo', 'deliver', resolutions=[{'finding_id': f['id'], 'change': 'Second correction'}
                                               for f in rejected['review_findings']])
        self.call('jhon', 'check', argv=['bash', 'tests/check.test.sh'], method='regression', criterion='one')
        self.call('jhon', 'approve', evidence='Correction verified')
        with self.assertRaisesRegex(ValueError, 'Falta commit local'): self.call('alex', 'complete')
        second = self.call('jhon', 'commit', message='fix: second candidate')['local_commit_result']['sha']
        self.assertNotEqual(first, second)

    def test_legacy_auto_green_can_still_be_rejected_after_resume(self):
        self.configure(fast='bash tests/check.test.sh')
        self.start()
        state = self.call('teo', 'deliver')
        state.pop('review_protocol')
        with sqlite3.connect(self.db_path) as db:
            db.execute('UPDATE agent_workflows SET body=? WHERE id=?', (json.dumps(state), state['id']))
        self.call('jhon', 'oracle', expected='one', negative='two', invariant='int', refutation='assert')
        result = self.call('jhon', 'reject', evidence='Generic check does not prove the behavior')
        self.assertEqual(result['state'], 'implementation_ready')


if __name__ == '__main__':
    # Reuse the fixture, not the inherited suite; run-all executes that separately.
    suite = unittest.TestSuite(ReviewCycle(name) for name in ReviewCycle.__dict__ if name.startswith('test_'))
    sys.exit(not unittest.TextTestRunner(verbosity=2).run(suite).wasSuccessful())
