"""Recovery must finish real work without resetting limits or inventing approval."""
import importlib.util
from contextlib import closing
import os
from pathlib import Path
import sqlite3
import subprocess
import shlex
import sys
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[1]
PACKAGE = Path(os.environ.get('SKALLING_RECOVERY_ROOT', ROOT))
sys.path.insert(0, str(PACKAGE / 'scripts'))
sys.dont_write_bytecode = True
spec = importlib.util.spec_from_file_location('fixtures', ROOT / 'tests/workflow-engine.test.py')
fixtures = importlib.util.module_from_spec(spec)
spec.loader.exec_module(fixtures)


class Recovery(unittest.TestCase):
    setUpClass = classmethod(fixtures.Workflow.setUpClass.__func__)
    tearDownClass = classmethod(fixtures.Workflow.tearDownClass.__func__)
    call = fixtures.Workflow.call

    def setUp(self):
        fixtures.Workflow.setUp(self)
        spec = importlib.util.spec_from_file_location('recovery_engine', PACKAGE / 'scripts/skalling-workflow.py')
        self.engine = importlib.util.module_from_spec(spec)
        spec.loader.exec_module(self.engine)

    def blocked(self, **extra):
        state = self.call('alex', 'start', risk='medium', scope='local', execution_mode='direct',
                          files=['app.py'], acceptance='value is one', reuse='app', **extra)
        for _ in range(3):
            self.call('teo', 'deliver', resolutions=[{'finding_id': f['id'], 'change': 'Correct candidate'}
                                                    for f in state.get('review_findings', [])])
            state = self.call('jhon', 'reject', evidence='Review condition not satisfied')
        self.assertEqual(state['state'], 'blocked')
        return state

    def recover(self, **extra):
        self.call('alex', 'feedback', feedback_id='user-correction', kind='correction',
                  evidence='Correct the process and finish; keep the public API unchanged')
        return self.call('alex', 'recover', feedback_id='user-correction',
                         evidence='Review expected a database row while handoff requested only a proposal',
                         recovery_plan='Pau persists the authorized decision; Jhon checks the row; finish', **extra)

    def test_recovery_completes_without_resetting_history_or_accepting_stale_approval(self):
        before = self.blocked(constraints=['Keep API'], non_goals=['Blog audit'], commit_policy='forbidden')
        state = self.recover()
        for field in ('intent', 'files', 'risk', 'delivery_number', 'review_findings', 'review_history',
                      'constraints', 'non_goals', 'commit_policy'):
            self.assertEqual(state[field], before[field], field)
        self.assertEqual(self.engine.public_response(state)['recommended_action']['deliveries_remaining'], 1)
        with self.assertRaises(ValueError):
            self.call('jhon', 'approve', evidence='Old review')
        self.call('teo', 'deliver', resolutions=[{'finding_id': f['id'], 'change': 'Persisted and checked row'}
                                                for f in state['review_findings']])
        self.call('jhon', 'oracle', expected='one', negative='two', invariant='integer', refutation='assert')
        self.call('jhon', 'check', argv=['python3', '-B', '-c', 'from app import value; assert value == 1'],
                  method='behavior', criterion='one')
        self.call('jhon', 'approve', evidence='Actual result checked')
        self.assertEqual(self.call('alex', 'complete')['state'], 'completed')
        with self.assertRaisesRegex(ValueError, 'prohíbe commits'):
            self.call('jhon', 'commit', message='unauthorized')

    def test_recovery_is_idempotent_and_cannot_repeat_or_reset_with_supersedes(self):
        self.blocked()
        state = self.recover()
        self.assertEqual(self.recover()['process_recovery'], state['process_recovery'])
        self.call('teo', 'deliver', resolutions=[{'finding_id': f['id'], 'change': 'Attempt correction'}
                                                for f in state['review_findings']])
        blocked = self.call('jhon', 'reject', evidence='Still incorrect')
        self.assertEqual(blocked['state'], 'blocked')
        self.assertEqual(blocked['delivery_number'], 4)
        self.assertIn('recuperación ya consumida', blocked['next_step'])
        with self.assertRaisesRegex(ValueError, 'ya fue utilizada'):
            self.recover(constraints=[])
        with self.assertRaisesRegex(ValueError, 'Presupuesto'):
            self.call('alex', 'start', id='retry', supersedes='request', risk='medium', scope='local',
                      files=['app.py'], acceptance='one', reuse='app')
        self.assertEqual(self.call('alex', 'status')['state'], 'blocked')

    def test_recovery_requires_user_feedback_actor_and_specific_plan(self):
        before = self.blocked()
        args = dict(feedback_id='missing', evidence='Observed error', recovery_plan='Concrete correction')
        with self.assertRaisesRegex(ValueError, 'feedback humano'):
            self.call('alex', 'recover', **args)
        with self.assertRaisesRegex(ValueError, 'Only Alex'):
            self.call('teo', 'recover', **args)
        self.call('alex', 'feedback', feedback_id='missing', kind='correction', evidence='Fix this')
        with self.assertRaisesRegex(ValueError, 'recovery_plan'):
            self.call('alex', 'recover', **{**args, 'recovery_plan': ''})
        self.assertEqual(self.call('alex', 'status')['review_history'], before['review_history'])

    def exhaust_recovery(self):
        self.blocked(constraints=['Keep API'], commit_policy='forbidden')
        state = self.recover()
        self.call('alex', 'feedback', feedback_id='older-instruction', kind='correction', evidence='Earlier instruction')
        self.call('teo', 'deliver', resolutions=[{'finding_id': f['id'], 'change': 'Attempt correction'}
                                               for f in state['review_findings']])
        return self.call('jhon', 'reject', evidence='Specific product defect remains')

    def test_new_human_instruction_grants_one_continuation_without_erasing_history(self):
        before = self.exhaust_recovery()
        self.call('alex', 'feedback', feedback_id='human-continue', kind='correction',
                  evidence='User explicitly requests correcting the remaining defect after this blocker')
        payload = dict(continuation=True, feedback_id='human-continue', evidence='Previous grant exhausted',
                       recovery_plan='Teo corrects the pending defect; Jhon verifies before approval')
        state = self.call('alex', 'recover', **payload)
        for field in ('delivery_number', 'process_recovery', 'review_history', 'review_findings',
                      'files', 'risk', 'constraints', 'commit_policy', 'outcomes'):
            self.assertEqual(state[field], before[field], field)
        self.assertEqual(state['state'], 'implementation_ready')
        self.assertEqual(self.engine.next_action(state)['deliveries_remaining'], 1)
        self.assertEqual(self.call('alex', 'recover', **payload)['authorized_continuations'], state['authorized_continuations'])
        with self.assertRaises(ValueError):
            self.call('jhon', 'approve', evidence='Cannot use old approval')
        self.call('teo', 'deliver', resolutions=[{'finding_id': f['id'], 'change': 'Defect corrected'}
                                               for f in state['review_findings'] if f['status'] != 'resolved'])
        self.call('jhon', 'oracle', expected='one', negative='two', invariant='integer', refutation='assert')
        self.call('jhon', 'check', argv=['python3', '-B', '-c', 'from app import value; assert value == 1'],
                  method='behavior', criterion='one')
        self.call('jhon', 'approve', evidence='Corrected result independently checked')
        self.assertEqual(self.call('alex', 'complete')['state'], 'completed')

    def test_continuation_rejects_old_consumed_or_non_corrective_authorizations(self):
        before = self.exhaust_recovery()
        self.call('alex', 'feedback', feedback_id='acceptance', kind='accepted', evidence='Thanks')
        for feedback_id in ('older-instruction', 'user-correction', 'acceptance', 'invented'):
            with self.subTest(feedback_id=feedback_id), self.assertRaises(ValueError):
                self.call('alex', 'recover', continuation=True, feedback_id=feedback_id,
                          evidence='Exhausted', recovery_plan='Correct remaining defect')
        after = self.call('alex', 'status')
        self.assertEqual(after['state'], 'blocked')
        self.assertEqual(after['review_history'], before['review_history'])
        self.assertFalse(after.get('authorized_continuations'))

    def test_human_instruction_and_continuation_are_atomic_and_idempotent(self):
        self.exhaust_recovery()
        payload = dict(continuation=True, feedback_id='atomic-continue', user_instruction='Continue and correct the remaining defect',
                       evidence='The previous recovery is exhausted', recovery_plan='Correct the defect and verify')
        state = self.call('alex', 'recover', **payload)
        self.assertEqual(state['state'], 'implementation_ready')
        self.assertEqual(sum(f['id'] == 'atomic-continue' for f in state['feedback']), 1)
        self.assertEqual(len(state['authorized_continuations']), 1)
        repeated = self.call('alex', 'recover', **payload)
        self.assertEqual(repeated['authorized_continuations'], state['authorized_continuations'])
        with closing(sqlite3.connect(self.db_path)) as db:
            self.assertEqual(db.execute("SELECT count(*) FROM agent_workflow_events WHERE action='feedback' AND json_extract(evidence,'$.id')='atomic-continue'").fetchone()[0], 1)

    def test_invalid_atomic_recovery_rolls_back_feedback_as_well_as_state(self):
        before = self.exhaust_recovery()
        with self.assertRaisesRegex(ValueError, 'recovery_plan'):
            self.call('alex', 'recover', continuation=True, feedback_id='bad-atomic',
                      user_instruction='Continue the correction', evidence='Blocked', recovery_plan='')
        after = self.call('alex', 'status')
        self.assertEqual(after['feedback'], before['feedback'])
        self.assertEqual(after['state'], 'blocked')
        with closing(sqlite3.connect(self.db_path)) as db:
            self.assertEqual(db.execute("SELECT count(*) FROM agent_workflow_events WHERE action='feedback' AND json_extract(evidence,'$.id')='bad-atomic'").fetchone()[0], 0)

    def test_each_later_continuation_needs_new_feedback_and_supersedes_retains_grants(self):
        self.exhaust_recovery()
        for number in (1, 2):
            self.call('alex', 'feedback', feedback_id=f'continue-{number}', kind='correction',
                      evidence=f'New user message after blocking event {number}: continue correcting')
            payload = dict(continuation=True, feedback_id=f'continue-{number}',
                           evidence='Remaining defect', recovery_plan='Correct and independently verify')
            with self.assertRaisesRegex(ValueError, 'Only Alex'):
                self.call('teo', 'recover', **payload)
            state = self.call('alex', 'recover', **payload)
            self.assertEqual(self.engine.delivery_limit(state), 4 + number)
            self.call('teo', 'deliver', resolutions=[{'finding_id': f['id'], 'change': 'Attempt correction'}
                                                   for f in state['review_findings'] if f['status'] != 'resolved'])
            blocked = self.call('jhon', 'reject', evidence='Still incorrect')
            # Lost response replay returns current state, never an extra attempt.
            self.assertEqual(self.call('alex', 'recover', **payload)['state'], 'blocked')
            with self.assertRaisesRegex(ValueError, 'ya fue utilizada'):
                self.call('alex', 'recover', **{**payload, 'evidence': 'Reworded same authorization'})
            with self.assertRaisesRegex(ValueError, 'Presupuesto'):
                self.call('alex', 'start', id='escape', supersedes='request', risk='medium', scope='local',
                          files=['app.py'], acceptance='one', reuse='app')
        self.assertEqual(blocked['delivery_number'], 6)

    def test_corrected_restrictions_are_explicit_and_user_budget_is_preserved(self):
        budget = {'max_checks': 1}
        before = self.blocked(constraints=['Only propose; do not write memory', 'Keep API'],
                              non_goals=['Blog audit'], commit_policy='forbidden', resource_budget=budget)
        self.call('alex', 'feedback', feedback_id='publish', kind='scope_change',
                  evidence='Persist the decision and commit; keep API and leave blog audit alone')
        args = dict(feedback_id='publish', evidence='Old handoff prohibits the required write',
                    recovery_plan='Persist decision, independently verify and commit',
                    constraints=['Keep API'], commit_policy='required')
        with self.assertRaisesRegex(ValueError, 'presupuesto'):
            self.call('alex', 'recover', **args, resource_budget={'max_checks': 100})
        state = self.call('alex', 'recover', **args)
        self.assertEqual(state['constraints'], ['Keep API'])
        self.assertEqual(state['non_goals'], before['non_goals'])
        self.assertEqual(state['resource_budget'], before['resource_budget'])
        self.assertEqual(state['budget_started_at'], before['budget_started_at'])
        self.assertEqual(state['commit_policy'], 'required')

    def test_supersedes_does_not_lose_used_recovery(self):
        self.blocked()
        self.recover()
        state = self.call('alex', 'start', id='replacement', supersedes='request', risk='medium', scope='local',
                          files=['app.py'], acceptance='one', reuse='app')
        self.assertEqual(state['delivery_number'], 3)
        self.assertIn('process_recovery', state)
        self.assertEqual(self.engine.next_action(state)['deliveries_remaining'], 1)

    def test_consumed_user_check_budget_stays_exhausted_after_recovery(self):
        state = self.call('alex', 'start', risk='medium', scope='local', execution_mode='direct',
                          files=['app.py'], acceptance='one', reuse='app', resource_budget={'max_checks': 1})
        for attempt in range(3):
            self.call('teo', 'deliver', resolutions=[{'finding_id': f['id'], 'change': 'Correct candidate'}
                                                    for f in state.get('review_findings', [])])
            if attempt == 0:
                self.call('jhon', 'oracle', expected='one', negative='two', invariant='integer', refutation='assert')
                self.call('jhon', 'check', argv=['python3', '-B', '-c', 'print(1)'],
                          method='diagnostic', criterion='one')
            state = self.call('jhon', 'reject', evidence='Result not covered')
        state = self.recover()
        self.call('teo', 'deliver', resolutions=[{'finding_id': f['id'], 'change': 'Corrected process'}
                                                for f in state['review_findings']])
        self.call('jhon', 'oracle', expected='one', negative='two', invariant='integer', refutation='assert')
        with self.assertRaisesRegex(ValueError, 'Presupuesto explícito agotado'):
            self.call('jhon', 'check', argv=['python3', '-B', '-c', 'print(1)'],
                      method='assertion', criterion='one')
        public = self.engine.public_response(self.call('alex', 'status'))
        self.assertEqual(public['execution_budget']['checks_started'], 1)

    def test_missing_memory_push_has_actionable_repair_before_document_approval(self):
        def git(*args):
            return subprocess.check_output(['git', '-C', str(self.root), *args], text=True).strip()
        previous = git('rev-parse', 'HEAD')
        decision = self.root / '.opencode/context/decisiones/adr-8.md'
        decision.parent.mkdir(parents=True)
        decision.write_text('# Accepted historical decision\n')
        git('add', str(decision))
        git('commit', '-qm', 'docs: historical decision')
        head = git('rev-parse', 'HEAD')
        self.call('alex', 'start', risk='high', scope='local', execution_mode='direct',
                  files=['app.py'], acceptance='one', reuse='app')
        hook = PACKAGE / ('hooks/git-gate.py' if (PACKAGE / 'hooks/git-gate.py').exists() else 'scripts/hooks/git-gate.py')
        def prepush():
            return subprocess.run([sys.executable, str(hook), 'pre-push'], cwd=self.root,
                                  input=f'refs/heads/main {head} refs/heads/main {previous}\n',
                                  text=True, capture_output=True)
        failed = prepush()
        self.assertNotEqual(failed.returncode, 0)
        self.assertIn('Tabla: decisions; slug: adr-8', failed.stderr)
        self.assertIn('teamdb-memory.sh', failed.stderr)
        self.assertIn('no exige cerrar action document', failed.stderr)
        # Actual authorized persistence, while workflow remains unreviewed.
        saved = subprocess.run(['bash', str(PACKAGE / 'scripts/teamdb-memory.sh'), '--project', str(self.root),
                                'decision', 'adr-8', 'Historical decision', 'Explicitly accepted; retained as history'],
                               capture_output=True, text=True)
        self.assertEqual(saved.returncode, 0, saved.stdout + saved.stderr)
        with closing(sqlite3.connect(self.db_path)) as db:
            self.assertEqual(db.execute("SELECT status FROM decisions WHERE slug='adr-8'").fetchone(), ('accepted',))
        self.assertEqual(self.call('alex', 'status')['state'], 'implementation_ready')
        passed = prepush()
        self.assertEqual(passed.returncode, 0, passed.stdout + passed.stderr)

    def test_navigation_indexes_commit_and_push_without_fake_memory_rows(self):
        def git(*args, check=True):
            result = subprocess.run(['git', '-C', str(self.root), *args], capture_output=True, text=True)
            if check:
                self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
            return result
        remote = tempfile.TemporaryDirectory()
        self.addCleanup(remote.cleanup)
        subprocess.run(['git', 'init', '--bare', '-q', remote.name], check=True)
        git('remote', 'add', 'fixture', remote.name)
        git('push', '-q', 'fixture', 'HEAD:refs/heads/main')
        hook = PACKAGE / ('hooks/git-gate.py' if (PACKAGE / 'hooks/git-gate.py').exists() else 'scripts/hooks/git-gate.py')
        for event in ('pre-commit', 'pre-push'):
            installed = self.root / '.git/hooks' / event
            installed.write_text(f'#!/bin/sh\nexec {shlex.quote(sys.executable)} {shlex.quote(str(hook))} {event} "$@"\n')
            installed.chmod(0o755)
        names = ['.opencode/context/' + folder + '/index.md'
                 for folder in ('decisiones', 'problemas-conocidos', 'followups')]
        names.append('.opencode/changes/index.md')
        for name in names:
            path = self.root / name
            path.parent.mkdir(parents=True, exist_ok=True)
            path.write_text('# Índice\n\n- [Entrada histórica](adr-8.md)\n')
        git('add', '--', *names)
        git('commit', '-qm', 'docs: navigation indexes')
        git('push', '-q', 'fixture', 'HEAD:refs/heads/main')
        self.assertEqual(git('ls-remote', 'fixture', 'refs/heads/main').stdout.split()[0],
                         git('rev-parse', 'HEAD').stdout.strip())
        with closing(sqlite3.connect(self.db_path)) as db:
            for table in ('decisions', 'known_problems', 'work_in_progress', 'plans'):
                self.assertEqual(db.execute(f"SELECT count(*) FROM {table} WHERE slug IN ('index','index.md')").fetchone()[0], 0)
        # Navigation classification never exempts the actual content from secret checks.
        path = self.root / names[0]
        path.write_text('# Índice\n' + 'ghp_' + 'A' * 25 + '\n')
        git('add', '--', names[0])
        blocked = git('commit', '-qm', 'must reject synthetic token', check=False)
        self.assertNotEqual(blocked.returncode, 0)
        self.assertIn('posible secreto', blocked.stderr)

    def test_recover_during_review_preserves_candidate_and_explains_next_step(self):
        self.call('alex', 'start', risk='medium', scope='local', execution_mode='direct',
                  files=['app.py'], acceptance='one', reuse='app')
        before = self.call('teo', 'deliver')
        with self.assertRaisesRegex(ValueError, 'fallo de Git no cambia el estado'):
            self.call('alex', 'recover', feedback_id='user-correction', evidence='Push hook rejected an index',
                      recovery_plan='Repair hook classification')
        after = self.call('alex', 'status')
        for field in ('state', 'delivery_number', 'digest', 'checks', 'oracle'):
            self.assertEqual(after[field], before[field])
        self.assertEqual(self.engine.public_response(after)['recommended_action']['agent'], 'jhon')


if __name__ == '__main__':
    unittest.main()
