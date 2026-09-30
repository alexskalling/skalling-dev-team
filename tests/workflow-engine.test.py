import importlib.util
import json
import os
import sys
import shutil
from pathlib import Path
from contextlib import closing
import sqlite3
import tempfile
import threading
import time
import unittest
import subprocess

ROOT = Path(__file__).resolve().parents[1]


class Workflow(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        # teamdb-init tarda ~2 s: se inicializa una vez y cada test copia la DB.
        cls.template = tempfile.TemporaryDirectory()
        subprocess.run(['bash', str(ROOT / 'scripts/teamdb-init.sh'), cls.template.name], check=True,
                       capture_output=True, env={**os.environ, 'SKALLING_ROOT': str(ROOT)})
        cls.template_db = Path(cls.template.name) / '.opencode/context/team.db'

    @classmethod
    def tearDownClass(cls):
        cls.template.cleanup()

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
        self.db_path = self.root / '.opencode/context/team.db'
        shutil.copyfile(self.template_db, self.db_path)
        with closing(sqlite3.connect(self.db_path)) as db, db:
            db.execute("INSERT OR REPLACE INTO schema_meta(key,value) VALUES('project_readiness','initialized')")
            db.execute("INSERT INTO concepts(slug,title,body_md,updated_at) VALUES('project-summary','Resumen','App de prueba',datetime('now'))")
            db.execute("INSERT INTO plans(slug,title,design_md,status) VALUES('plan','Plan','# diseño','approved')")
            self.plan_id = db.execute("SELECT id FROM plans WHERE slug='plan'").fetchone()[0]

    def test_complete_reconciles_only_bound_tasks_and_finishes_routing(self):
        with sqlite3.connect(self.db_path) as db:
            ids = [db.execute("INSERT INTO tasks(plan_id,slug,title,acceptance_md) VALUES(?,?,?,?)",
                              (self.plan_id, slug, slug, 'value remains one')).lastrowid for slug in ('first', 'second')]
        self.call('alex', 'start', risk='medium', scope='module', files=['app.py'],
                  acceptance='value remains one', reuse='existing', execution_mode='staged')
        self.call('sol', 'plan', evidence='reuse the current module')
        self.call('sol', 'ready', plan_id=self.plan_id, task_ids=[ids[0]], evidence='only first task')
        self.verify()
        self.call('alex', 'complete')
        self.call('alex', 'complete')  # retries after a lost response must be harmless
        with sqlite3.connect(self.db_path) as db:
            self.assertEqual(db.execute('SELECT status FROM tasks ORDER BY id').fetchall(), [('resolved',), ('pending',)])
            self.assertEqual(db.execute('SELECT status FROM plans WHERE id=?', (self.plan_id,)).fetchone()[0], 'in_progress')
            self.assertEqual(db.execute('SELECT outcome FROM routing_decisions').fetchone()[0], 'SUCCESS')
            self.assertEqual(db.execute("SELECT count(*) FROM agent_workflow_events WHERE action='complete'").fetchone()[0], 1)

    def test_plan_binding_requires_explicit_tasks_and_rolls_back_invalid_selection(self):
        with sqlite3.connect(self.db_path) as db:
            db.execute("INSERT INTO tasks(plan_id,slug,title) VALUES(?,'first','First')", (self.plan_id,))
        self.call('alex', 'start', risk='medium', scope='module', files=['app.py'], acceptance='one', reuse='existing')
        self.call('sol', 'plan', evidence='approved design')
        for extra in ({}, {'task_ids': [999]}):
            with self.assertRaisesRegex(ValueError, 'task'):
                self.call('sol', 'ready', plan_id=self.plan_id, evidence='ready', **extra)
        self.assertEqual(self.call('alex', 'status')['state'], 'planned')

    def test_last_task_completes_plan_and_failure_rolls_back_all_state(self):
        from unittest.mock import patch
        with sqlite3.connect(self.db_path) as db:
            task = db.execute("INSERT INTO tasks(plan_id,slug,title,acceptance_md) VALUES(?,'only','Only task','value one')", (self.plan_id,)).lastrowid
        self.call('alex', 'start', risk='medium', scope='module', files=['app.py'], acceptance='value one', reuse='existing')
        self.call('sol', 'plan', evidence='design is approved')
        self.call('sol', 'ready', plan_id=self.plan_id, task_ids=[task], evidence='all work selected')
        self.verify()
        original = self.engine.finish_lifecycle
        def interrupted(db, state, now):
            original(db, state, now)
            raise ValueError('Simulated interruption before commit')
        with patch.object(self.engine, 'finish_lifecycle', side_effect=interrupted):
            with self.assertRaisesRegex(ValueError, 'Simulated interruption'):
                self.call('alex', 'complete')
        with sqlite3.connect(self.db_path) as db:
            self.assertEqual(db.execute('SELECT status FROM tasks').fetchone()[0], 'in_review')
            self.assertEqual(db.execute('SELECT outcome FROM routing_decisions').fetchone()[0], 'PENDING')
        self.assertEqual(self.call('alex', 'status')['state'], 'verified')
        self.call('alex', 'complete')
        with sqlite3.connect(self.db_path) as db:
            self.assertEqual(db.execute('SELECT status FROM plans').fetchone()[0], 'completed')
            self.assertEqual(db.execute('SELECT status FROM tasks').fetchone()[0], 'resolved')

    def test_cancel_closes_metrics_without_claiming_success(self):
        self.start()
        result = self.call('alex', 'cancel', evidence='User cancelled this request')
        self.assertEqual(result['state'], 'cancelled')
        with sqlite3.connect(self.db_path) as db:
            self.assertEqual(db.execute('SELECT outcome FROM workflow_metrics').fetchone()[0], 'cancelled')
            self.assertEqual(db.execute('SELECT outcome FROM routing_decisions').fetchone()[0], 'FAIL')
        with self.assertRaises(ValueError):
            self.call('teo', 'deliver')

    def test_goal_survives_handoffs_and_requires_all_outcomes(self):
        self.call('alex', 'start', risk='low', scope='local', files=['app.py'],
                  acceptance='value remains one', reuse='existing', intent='Keep totals correct',
                  outcomes=[{'id': 'value', 'expected': 'value is one'},
                            {'id': 'type', 'expected': 'value is integer'}])
        delivered = self.call('teo', 'deliver')
        self.assertEqual(self.engine.public_response(delivered)['intent'], 'Keep totals correct')
        self.call('jhon', 'oracle', expected='one', negative='two', invariant='int', refutation='assert')
        self.call('jhon', 'check', argv=['python3', '-c', 'from app import value; assert value == 1'],
                  method='assertion', criterion='value')
        request = {'project': str(self.root), 'actor': 'jhon', 'session': 'jhon-session',
                   'action': 'approve', 'payload': {'id': 'request', 'evidence': 'checked',
                       'coverage': [{'outcome_id': 'value', 'check_index': 0, 'observation': 'one'}]}}
        with self.assertRaisesRegex(ValueError, 'Every outcome'):
            self.engine.operate(request)
        request['payload']['coverage'].append({'outcome_id': 'type', 'check_index': 0, 'observation': 'integer'})
        approved = self.engine.operate(request)
        self.assertEqual(len(approved['coverage']), 2)

    def test_identical_deterministic_check_executes_once_and_invalidates_on_change(self):
        self.start()
        self.call('teo', 'deliver')
        self.call('jhon', 'oracle', expected='one', negative='two', invariant='integer', refutation='assert')
        payload = dict(argv=['bash', 'tests/check.test.sh'], method='assert', criterion='value', reusable=True)
        self.call('jhon', 'check', **payload)
        from unittest.mock import patch
        with patch.object(self.engine, 'run_bounded', side_effect=AssertionError('duplicate execution')):
            result = self.call('jhon', 'check', **payload)
        self.assertEqual(result['checks'][-1]['reused_from'], 0)
        (self.root / 'configuration.txt').write_text('changed dependency')
        with patch.object(self.engine, 'run_bounded', return_value=(0, 'fresh')) as run:
            result = self.call('jhon', 'check', **payload)
        run.assert_called_once()
        self.assertNotIn('reused_from', result['checks'][-1])

    def test_feedback_is_explicit_idempotent_and_does_not_reopen_completion(self):
        self.start()
        self.verify()
        self.call('alex', 'complete')
        result = self.call('alex', 'feedback', feedback_id='user-message-1', kind='correction',
                           evidence='User says the empty state is still wrong')
        self.assertEqual(result['human_corrections'], 1)
        again = self.call('alex', 'feedback', feedback_id='user-message-1', kind='correction',
                          evidence='User says the empty state is still wrong')
        self.assertEqual(again['human_corrections'], 1)
        self.assertEqual(again['state'], 'completed')

    def configure(self, **commands):
        lines = ['testing:']
        for name, command in commands.items():
            lines += [f'  {name}:', '    available: true', f'    command: "{command}"']
        (self.root / '.opencode/project.yaml').write_text('\n'.join(lines) + '\n')

    def call(self, actor, action, **payload):
        if action == 'start':
            payload.setdefault('intent', 'Preserve the fixture API and value')
        if action in {'approve', 'complete', 'prepare_commit'} and 'coverage' not in payload:
            with closing(sqlite3.connect(self.db_path)) as db:
                row = db.execute("SELECT body FROM agent_workflows WHERE id='request'").fetchone()
            state = json.loads(row[0]) if row else {}
            checks = state.get('checks', [])
            eligible = [i for i, c in enumerate(checks) if c['agent'] == actor or actor in {'alex', 'teo'}]
            if eligible:
                payload['coverage'] = [{'outcome_id': o['id'], 'check_index': eligible[-1],
                                        'observation': 'Fixture assertion verified value remains one'}
                                       for o in state.get('outcomes', [{'id': 'acceptance'}])]
        return self.engine.operate({'project': str(self.root), 'actor': actor, 'session': actor+'-session',
                                    'action': action, 'payload': {'id': 'request', **payload}})

    def start(self, risk='low', execution_mode=None):
        payload = {'risk': risk, 'files': ['app.py', 'tests/check.test.sh'],
                   'acceptance': 'value remains one', 'scope': 'local', 'decision': 'none',
                   'reuse': 'app.py existente'}
        if execution_mode:
            payload['execution_mode'] = execution_mode
        return self.call('alex', 'start', **payload)

    def verify(self):
        self.call('teo', 'deliver')
        self.call('jhon', 'oracle', expected='value one', negative='value two', invariant='integer', refutation='test value')
        self.call('jhon', 'check', argv=['bash', 'tests/check.test.sh'], method='falsification', criterion='value stays 1')
        return self.call('jhon', 'approve', evidence='falsification check covers the declared acceptance criterion')

    def assert_role_can_commit_verified_unit(self, actor, risk):
        if risk == 'low':
            self.configure(fast='bash tests/check.test.sh')
        self.start(risk, execution_mode='focused')
        (self.root / 'tests/check.test.sh').write_text('test "$(cat app.py)" = "value = 1"  # verificado\n')
        if risk == 'low':
            self.call('teo', 'deliver')
        else:
            self.verify()
        if risk == 'high':
            with self.assertRaisesRegex(ValueError, 'verification for this risk'):
                self.call('jhon', 'prepare_commit')
            self.call('luz', 'check', argv=['bash', 'tests/check.test.sh'], method='risk', criterion='value stays 1')
            self.call('luz', 'approve', evidence='risk checked', findings='no additional risk')
        before = self.call('alex', 'status')
        # A project agent replaces the global header in OpenCode. Exercise the
        # minimal local override that previously dropped commit permissions.
        config_spec = importlib.util.spec_from_file_location('project_config', ROOT / 'scripts/skalling-project-config.py')
        config = importlib.util.module_from_spec(config_spec)
        config_spec.loader.exec_module(config)
        name = actor.capitalize()
        agent_dir = self.root / '.opencode/agents'
        agent_dir.mkdir()
        (agent_dir / f'{name}.md').write_text('---\nmodel: fixture/local\n---\nFixture\n')
        config.apply_test_commands(self.root)
        script = '''
import fs from 'node:fs';
import assert from 'node:assert/strict';
const {configBashRules, agentBashRules, decideRules} = await import(process.argv[1] + '/plugins/lib/workflow.mjs');
const {createCore} = await import(process.argv[1] + '/plugins/lib/git-guard.mjs');
const fixture = JSON.parse(fs.readFileSync(0, 'utf8'));
const rules = [...configBashRules(JSON.stringify({permission:fixture.policy})), ...agentBashRules(fixture.header)];
assert.equal(decideRules(rules, 'git commit -m fix'), 'allow');
assert.equal(decideRules(rules, 'git push origin main'), 'ask');
assert.equal(createCore().decide({tool:'shell',agent:fixture.actor,input:{command:'git commit -m fix'}}), null);
'''
        policy_check = subprocess.run(['node', '--input-type=module', '-e', script, str(ROOT)],
            input=json.dumps({'policy': config.policy_permissions(), 'header': (agent_dir / f'{name}.md').read_text(),
                              'actor': actor}), text=True, capture_output=True)
        self.assertEqual(policy_check.returncode, 0, policy_check.stderr)
        self.assertTrue(self.engine.public_response(before)['local_commit']['ready'])
        self.assertEqual(self.engine.public_response(before)['local_commit']['delegate_to'],
                         'luz' if before['risk'] == 'high' else 'jhon')
        self.assertIn(before['id'], self.engine.public_response(before)['local_commit']['handoff'])
        prepared = self.call(actor, 'prepare_commit')
        self.assertEqual(prepared['state'], before['state'], 'Commit preparation must not bypass workflow completion')
        self.assertEqual(len(prepared['checks']), len(before['checks']), 'Do not rerun verification to commit')
        self.assertTrue(prepared['receipt_tree_hash'])
        base = subprocess.check_output(['git', 'rev-parse', 'HEAD'], cwd=self.root, text=True).strip()
        hook = self.root / '.git/hooks/pre-commit'
        hook.write_text(f'#!/bin/sh\nexec python3 "{ROOT / "scripts/hooks/git-gate.py"}" pre-commit\n')
        hook.chmod(0o755)
        committed = subprocess.run(['git', 'commit', '-qm', f'fix: unidad verificada por {actor}'],
                                   cwd=self.root, capture_output=True, text=True)
        self.assertEqual(committed.returncode, 0, committed.stderr)
        completed = self.call('alex', 'complete')
        self.assertEqual(completed['state'], 'completed')
        self.assertEqual(completed['receipt_tree_hash'], prepared['receipt_tree_hash'])
        # A model may ask to prepare again after Alex completed. This is a
        # recovery, not a reason to repeat review or discard the valid receipt.
        resumed = self.call(actor, 'prepare_commit')
        self.assertEqual(resumed['state'], 'completed')
        self.assertEqual(resumed['receipt_tree_hash'], prepared['receipt_tree_hash'])
        self.assertEqual(len(resumed['checks']), len(before['checks']))
        head = subprocess.check_output(['git', 'rev-parse', 'HEAD'], cwd=self.root, text=True).strip()
        push_gate = subprocess.run(['python3', str(ROOT / 'scripts/hooks/git-gate.py'), 'pre-push'],
                                   input=f'refs/heads/main {head} refs/heads/main {base}\n',
                                   cwd=self.root, capture_output=True, text=True)
        self.assertEqual(push_gate.returncode, 0, push_gate.stderr)
        (self.root / 'app.py').write_text('value = 2\n')
        with self.assertRaisesRegex(ValueError, 'Candidate changed'):
            self.call(actor, 'prepare_commit')

    def test_teo_can_commit_auto_verified_unit_without_waiting_for_alex(self):
        self.assert_role_can_commit_verified_unit('teo', 'low')

    def test_jhon_can_commit_verified_unit_without_waiting_for_alex(self):
        self.assert_role_can_commit_verified_unit('jhon', 'medium')

    def test_luz_can_commit_reviewed_high_risk_unit_without_waiting_for_alex(self):
        self.assert_role_can_commit_verified_unit('luz', 'high')

    def test_commit_preparation_rejects_unverified_candidate_or_wrong_role(self):
        self.start('medium')
        with self.assertRaises(ValueError):
            self.call('teo', 'prepare_commit')
        self.verify()
        for actor in ('alex', 'pol', 'sol', 'jes', 'pau'):
            with self.subTest(actor=actor), self.assertRaises(ValueError):
                self.call(actor, 'prepare_commit')
        (self.root / 'app.py').write_text('value = 2\n')
        with self.assertRaisesRegex(ValueError, 'Candidate changed'):
            self.call('jhon', 'prepare_commit')

    def test_local_commit_does_not_hide_undeclared_changes_from_workflow(self):
        self.start()
        (self.root / 'extra.py').write_text('value = 5\n')
        subprocess.run(['git', 'add', 'extra.py'], cwd=self.root, check=True)
        subprocess.run(['git', 'commit', '-qm', 'unrelated unit'], cwd=self.root, check=True)
        with self.assertRaisesRegex(ValueError, 'Scope creep'):
            self.call('teo', 'deliver')

    def test_reopening_review_revokes_prepared_commit_approval(self):
        self.configure(fast='test -f app.py')
        self.start()
        (self.root / 'app.py').write_text('value = 2\n')
        self.call('teo', 'deliver')
        prepared = self.call('teo', 'prepare_commit')
        reviewed = self.call('jhon', 'oracle', expected='one', negative='two', invariant='int', refutation='test value')
        self.assertNotIn('receipt_tree_hash', reviewed)
        with closing(sqlite3.connect(self.db_path)) as db:
            verdict = db.execute('SELECT exit_code, command FROM receipts WHERE tree_hash=? ORDER BY ts DESC, rowid DESC',
                                 (prepared['receipt_tree_hash'],)).fetchone()
        self.assertEqual(verdict, (1, 'skalling_workflow:review-reopened'))

    def test_prepare_commit_does_not_include_unreviewed_staged_files(self):
        self.start('medium')
        self.verify()
        extra = self.root / '.opencode/plugin.js'
        extra.write_text('unreviewed();\n')
        subprocess.run(['git', 'add', str(extra)], cwd=self.root, check=True)
        with self.assertRaisesRegex(ValueError, 'outside the reviewed scope'):
            self.call('jhon', 'prepare_commit')

    def test_existing_user_changes_are_preserved_but_new_edits_still_need_scope(self):
        other = self.root / 'user.txt'
        other.write_text('previous user work')
        started = self.start()
        self.call('teo', 'deliver')
        other.write_text('changed during workflow')
        with self.assertRaisesRegex(ValueError, 'Scope creep'):
            self.engine.require_scope(self.root, ['app.py', 'tests/check.test.sh'],
                                      self.engine.base_head(self.root),
                                      started['external_baseline'])

    def assert_isolated_commit_preserves_foreign_work(self, committer):
        unborn = self.engine.base_head(self.root) is None
        other = self.root / 'user.txt'
        other.write_text('previous user work')
        extra = self.root / '.opencode/plugin.js'
        extra.write_text('staged tooling\n')
        subprocess.run(['git', 'add', str(extra)], cwd=self.root, check=True)
        staged = subprocess.check_output(['git', 'ls-files', '-s', '--', '.opencode/plugin.js'], cwd=self.root)
        extra.write_text('newer tooling in working tree\n')
        self.start('medium')
        (self.root / 'tests/check.test.sh').write_text('test "$(cat app.py)" = "value = 1" # reviewed\n')
        verified = self.verify()
        hook = self.root / '.git/hooks/pre-commit'
        hook.write_text(f'#!/bin/sh\nexec python3 "{ROOT / "scripts/hooks/git-gate.py"}" pre-commit\n')
        hook.chmod(0o755)
        with self.assertRaisesRegex(ValueError, 'Only Teo'):
            self.call('alex', 'commit', message='fix: verified unit')
        committed = self.call(committer, 'commit', message='fix: verified unit')
        sha = committed['local_commit_result']['sha']
        names = subprocess.check_output(['git', 'diff-tree', '--root', '--no-commit-id', '--name-only', '-r', sha], cwd=self.root, text=True)
        self.assertEqual(set(names.splitlines()), {'app.py', 'tests/check.test.sh'} if unborn else {'tests/check.test.sh'})
        self.assertEqual(staged, subprocess.check_output(['git', 'ls-files', '-s', '--', '.opencode/plugin.js'], cwd=self.root))
        self.assertEqual(extra.read_text(), 'newer tooling in working tree\n')
        self.assertEqual(other.read_text(), 'previous user work')
        self.assertEqual(len(committed['checks']), len(verified['checks']))
        for actor in ('teo', 'luz'):
            retried = self.call(actor, 'commit', message='fix: verified unit')
            self.assertEqual(retried['local_commit_result']['sha'], sha)
        self.assertEqual(self.call('alex', 'complete')['state'], 'completed')

    def test_jhon_isolated_commit_preserves_tooling_index_and_user_work(self):
        self.assert_isolated_commit_preserves_foreign_work('jhon')

    def test_teo_isolated_commit_preserves_tooling_index_and_user_work(self):
        self.assert_isolated_commit_preserves_foreign_work('teo')

    def test_luz_isolated_commit_preserves_tooling_index_and_user_work(self):
        self.assert_isolated_commit_preserves_foreign_work('luz')

    def test_old_workflow_recovers_external_changes_with_explicit_provenance(self):
        self.start()
        other = self.root/'user.txt'; other.write_text('user added after start')
        with self.assertRaisesRegex(ValueError, 'Scope creep'):
            self.call('teo', 'deliver')
        for actor in ('teo', 'pau'):
            with self.assertRaises(ValueError):
                self.call(actor, 'preserve_external', files=['user.txt'], evidence='not my task')
        with self.assertRaises(ValueError):
            self.call('alex', 'preserve_external', files=['app.py'], evidence='cannot hide own edits')
        self.call('alex', 'preserve_external', files=['user.txt'], evidence='User message confirms their separate edit')
        self.assertEqual(self.call('teo', 'deliver')['state'], 'verification_ready')

    def test_runtime_bundle_can_be_reviewed_separately_but_context_stays_private(self):
        runtime = self.root/'.opencode/plugins/local.js'
        runtime.parent.mkdir(); runtime.write_text('export const enabled = true;\n')
        for name in ('.opencode/context/team.db', '.opencode/context/note.md', '.env', '.git/config', '.opencode'):
            with self.subTest(name=name), self.assertRaises(ValueError):
                self.engine.scoped(self.root, name)
        with self.assertRaisesRegex(ValueError, 'risk high'):
            self.call('alex', 'start', risk='low', scope='local', files=['.opencode/plugins/local.js'],
                      acceptance='plugin enabled', reuse='runtime', execution_mode='focused')
        self.call('alex', 'start', risk='high', scope='local', files=['.opencode/plugins/local.js'],
                  acceptance='plugin enabled', reuse='runtime', execution_mode='focused')
        self.call('teo', 'deliver')
        self.call('jhon', 'oracle', expected='enabled true', negative='enabled false', invariant='runtime export', refutation='read export')
        self.call('jhon', 'check', argv=['python3', '-c', 'from pathlib import Path; assert "enabled = true" in Path(".opencode/plugins/local.js").read_text()'],
                  method='export assertion', criterion='plugin enabled')
        self.call('jhon', 'approve', evidence='assertion confirms enabled export')
        with self.assertRaisesRegex(ValueError, 'verification for this risk'):
            self.call('teo', 'commit', message='chore: runtime')
        self.call('luz', 'check', argv=['python3', '-c', 'from pathlib import Path; assert Path(".opencode/plugins/local.js").read_text() == "export const enabled = true;\\n"'],
                  method='inspect entire plugin', criterion='no executable side effects')
        self.call('luz', 'approve', evidence='pure export only', findings='No IO or side effects')
        self.assertTrue(self.call('luz', 'commit', message='chore: runtime')['local_commit_result']['created'])

    def test_isolated_commit_hook_failure_leaves_index_and_head_intact(self):
        self.start('medium')
        (self.root / 'tests/check.test.sh').write_text('test "$(cat app.py)" = "value = 1" # reviewed\n')
        self.verify()
        index = self.root / '.git/index'
        before = index.read_bytes()
        head = self.engine.base_head(self.root)
        hook = self.root / '.git/hooks/pre-commit'
        hook.write_text('#!/bin/sh\nexit 1\n'); hook.chmod(0o755)
        with self.assertRaisesRegex(ValueError, 'git commit'):
            self.call('teo', 'commit', message='fix: verified unit')
        self.assertEqual(index.read_bytes(), before)
        self.assertEqual(self.engine.base_head(self.root), head)
        self.assertFalse((self.root / '.git/index.lock').exists())

    def test_first_commit_uses_verified_unit_and_preserves_foreign_staging(self):
        subprocess.run(['git', 'checkout', '--orphan', 'first'], cwd=self.root, check=True, capture_output=True)
        self.assert_isolated_commit_preserves_foreign_work('jhon')

    def test_index_busy_never_removes_another_process_lock(self):
        self.start('medium'); self.verify()
        lock = self.root/'.git/index.lock'; lock.write_text('another process')
        with self.assertRaisesRegex(ValueError, 'ocupado'):
            self.call('jhon', 'commit', message='fix: verified unit')
        self.assertEqual(lock.read_text(), 'another process')

    def test_focused_sensitive_work_has_review_without_mandatory_planning(self):
        state = self.call('alex', 'start', risk='high', scope='local', files=['app.py'],
                          acceptance='value stays one', reuse='existing app', execution_mode='focused')
        self.assertEqual(state['state'], 'implementation_ready')
        self.call('teo', 'deliver')
        self.call('jhon', 'oracle', expected='one', negative='two', invariant='integer', refutation='test')
        self.call('jhon', 'check', argv=['python3', '-B', '-c', 'import app; assert app.value == 1'],
                  method='test', criterion='value one', reusable=True)
        self.call('jhon', 'approve', evidence='value verified')
        self.call('luz', 'reuse', check_index=0, evidence='same deterministic local check; risk reviewed')
        self.call('luz', 'approve', evidence='reviewed', findings='no additional data or privilege path')
        self.assertEqual(self.call('alex', 'complete')['state'], 'completed')

    def test_reuse_invalidates_when_an_undeclared_dependency_changes(self):
        self.call('alex', 'start', risk='high', scope='local', files=['app.py'],
                  acceptance='value one', reuse='app', execution_mode='focused')
        self.call('teo', 'deliver')
        self.call('jhon', 'oracle', expected='one', negative='two', invariant='integer', refutation='test')
        self.call('jhon', 'check', argv=['true'], method='test', criterion='one', reusable=True)
        self.call('jhon', 'approve', evidence='reviewed')
        (self.root / 'dependency.py').write_text('changed = True')
        with self.assertRaisesRegex(ValueError, 'environment|workspace'):
            self.call('luz', 'reuse', check_index=0, evidence='reuse')

    def test_infrastructure_retry_keeps_history_without_returning_to_implementation(self):
        self.start()
        self.call('teo', 'deliver')
        self.call('jhon', 'oracle', expected='one', negative='two', invariant='integer', refutation='test')
        argv = ['python3', '-c', 'import os,sys; sys.exit(0 if os.environ.get("SKALLING_TEST_READY") else 1)']
        self.call('jhon', 'check', argv=argv, method='test', criterion='environment ready')
        from unittest.mock import patch
        with patch.dict(os.environ, {'SKALLING_TEST_READY': '1'}):
            state = self.call('jhon', 'check', argv=argv, method='test', criterion='environment ready',
                              retry_of=0, failure_kind='infrastructure', evidence='dependency environment repaired')
        self.assertEqual(len(state['checks']), 2)
        self.assertEqual(state['checks'][0]['superseded_by'], 1)
        self.assertEqual(self.call('jhon', 'approve', evidence='retry verified')['state'], 'verified')

    def test_compact_response_does_not_repeat_success_logs(self):
        state = {'id': 'x', 'state': 'verified', 'risk': 'low', 'files': ['app.py'],
                 'oracle': {'expected': 'value one', 'negative': 'value two',
                            'invariant': 'integer', 'refutation': 'test value'},
                 'checks': [{'output': 'x' * 16000, 'exit_code': 0,
                             'criterion': 'value stays 1', 'method': 'falsification'}],
                 'verification': {'output': 'x' * 16000, 'exit_code': 0}}
        response = self.engine.public_response(state)
        self.assertLess(len(json.dumps(response)), 2000)
        self.assertEqual(response['check_count'], 1)
        self.assertNotIn('output', response['checks'][0])
        self.assertEqual(response['oracle'], state['oracle'])
        self.assertEqual(response['checks'][0]['criterion'], 'value stays 1')
        self.assertEqual(response['checks'][0]['method'], 'falsification')

    def test_clear_local_request_defaults_to_focused_when_model_omits_mode(self):
        state = self.call('alex', 'start', risk='low', scope='local', files=['app.py'],
                          acceptance='value remains one', reuse='existing app')
        self.assertEqual(state['execution_mode'], 'focused')
        self.assertEqual(state['state'], 'implementation_ready')
        self.assertEqual(state['route'], 'FAST-TRACK')

    def test_clear_local_medium_defaults_to_focused_and_dispatches_jhon(self):
        state = self.call('alex', 'start', risk='medium', scope='local', files=['app.py'],
                          acceptance='value remains one', reuse='existing app')
        self.assertEqual(state['execution_mode'], 'focused')
        self.assertEqual(state['state'], 'implementation_ready')
        self.assertEqual(state['route'], 'DIRECT')
        self.assertIn('Jhon', state['agents'])
        self.assertNotIn('Sol', state['agents'])

    def test_focused_cannot_bypass_module_scope_or_sensitive_review(self):
        with self.assertRaisesRegex(ValueError, 'focused requires'):
            self.call('alex', 'start', risk='medium', scope='module', files=['app.py'],
                      acceptance='value remains one', reuse='existing app', execution_mode='focused')
        with self.assertRaisesRegex(ValueError, 'focused requires'):
            self.call('alex', 'start', risk='high', scope='local', files=['app.py'], sensitive=True,
                      acceptance='value remains one', reuse='existing app', execution_mode='focused')

    def test_medium_route_reaches_implementation_with_real_plan_helpers(self):
        # Caso real (sesión 2026-09-28): Sol mandó ready con plan_id 1 (el
        # número del ejemplo de su prompt) y el equipo creyó que no había
        # transición de planned a implementation_ready. Los demás tests
        # insertan el plan directo en la base; este usa los helpers reales.
        scripts = ROOT / 'scripts'
        env = {k: v for k, v in os.environ.items() if not k.startswith(('SKALLING_', 'TEAMDB_'))}
        self.assertEqual(self.start(risk='medium', execution_mode='staged')['state'], 'clarified')
        self.assertIn('Sol: plan', self.call('alex', 'status')['next_step'])
        self.assertEqual(self.call('sol', 'plan', evidence='diseño: cambiar app.py; rollback: git revert')['state'], 'planned')
        with self.assertRaises(ValueError) as wrong:
            self.call('sol', 'ready', evidence='listo', plan_id=999)
        self.assertIn('Planes en TeamDB', str(wrong.exception))
        self.assertIn('teamdb-plan-approve.sh', str(wrong.exception))
        created = subprocess.run(['bash', str(scripts / 'teamdb-plan.sh'), str(self.root), 'cambio-valor', 'Cambio de valor', '-',
                                  '--purpose', 'Cambiar el valor de app.py', '--acceptance', 'value remains one'],
                                 input='- [ ] Ajustar app.py\n', capture_output=True, text=True, env=env)
        self.assertEqual(created.returncode, 0, created.stderr)
        with closing(sqlite3.connect(self.db_path)) as db:
            plan_id = db.execute("SELECT id FROM plans WHERE slug='cambio-valor'").fetchone()[0]
        approved = subprocess.run(['bash', str(scripts / 'teamdb-plan-approve.sh'), str(self.root), str(plan_id),
                                   'Diseño: app.py conserva el valor uno', 'Aceptación: value remains one',
                                   'Aprobado por el usuario en el pedido'], capture_output=True, text=True, env=env)
        self.assertEqual(approved.returncode, 0, approved.stderr)
        with sqlite3.connect(self.db_path) as db:
            task_ids = [r[0] for r in db.execute('SELECT id FROM tasks WHERE plan_id=?', (plan_id,))]
        ready = self.call('sol', 'ready', evidence='plan aprobado', plan_id=plan_id, task_ids=task_ids)
        self.assertEqual(ready['state'], 'implementation_ready')
        self.assertIn('Teo', ready['next_step'])

    def test_rejection_says_state_and_who_acts_next(self):
        self.start(risk='medium', execution_mode='staged')
        with self.assertRaises(ValueError) as early:
            self.call('jhon', 'approve', evidence='antes de tiempo')
        self.assertIn('Estado del workflow: clarified', str(early.exception))
        self.assertIn('Siguiente paso: Sol: plan', str(early.exception))

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
        with self.assertRaises(ValueError):
            self.call('sol', 'ready', evidence='dependencies ready')
        self.call('sol', 'ready', evidence='dependencies ready', plan_id=self.plan_id)
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
            self.call('alex', 'start', risk='low', files=['../outside'], acceptance='x', scope='local', decision='none', reuse='x')

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
        with self.assertRaisesRegex(ValueError, 'Siguiente paso: Teo: reintenta rescope'):
            self.call('teo', 'rescope', files=['extra.py'], evidence='')
        self.assertEqual(self.call('alex', 'status')['state'], 'implementation_ready')

    def test_delivery_identity_classifies_added_modified_deleted(self):
        (self.root / 'tests/old.py').write_text('legacy = 1\n')
        subprocess.run(['git', '-C', str(self.root), 'add', '-A'], check=True)
        subprocess.run(['git', '-C', str(self.root), 'commit', '-q', '-m', 'add old.py'], check=True)
        self.call('alex', 'start', risk='low', files=['app.py', 'tests/check.test.sh', 'tests/old.py', 'extra.py'],
                  acceptance='x', scope='local', decision='none', reuse='x')
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
        rejected = self.call('jhon', 'reject', evidence='needs another pass',
                             findings='La salida conserva el centrado; alinear el wrapper a la derecha')
        self.assertEqual(rejected['delivery']['delivery_number'], 1)
        second = self.call('teo', 'deliver')
        self.assertEqual(second['delivery']['delivery_number'], 2)

    def test_rejection_carries_specific_fix_and_delivery_budget(self):
        self.start()
        self.call('teo', 'deliver')
        state = self.call('jhon', 'reject', evidence='computed style still centered',
                          findings='Cambiar el wrapper .users-table a justify-content:flex-end')
        public = self.engine.public_response(state)
        self.assertEqual(public['last_rejection']['reason'], 'Cambiar el wrapper .users-table a justify-content:flex-end')
        self.assertEqual(public['recommended_action']['agent'], 'teo')
        self.assertEqual(public['recommended_action']['deliveries_remaining'], 2)

    def test_third_rejected_delivery_blocks_same_workflow(self):
        self.start()
        for attempt in range(1, self.engine.MAX_DELIVERIES + 1):
            self.call('teo', 'deliver')
            result = self.call('jhon', 'reject', evidence=f'candidate {attempt} still fails',
                               findings=f'failure detail {attempt}')
        self.assertEqual(result['state'], 'blocked')
        public = self.engine.public_response(result)
        self.assertEqual(public['recommended_action']['action'], 'stop_and_reclassify')
        self.assertEqual(public['recommended_action']['deliveries_remaining'], 0)
        with self.assertRaisesRegex(ValueError, 'blocked'):
            self.call('teo', 'deliver')

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
                             'files': ['app.py'], 'acceptance': 'x', 'scope': 'local', 'decision': 'none',
                             'reuse': 'x', 'intent': 'Preserve value'}})
        concurrent_duration = time.monotonic() - concurrent_start
        thread.join()

        self.assertLess(concurrent_duration, 0.5, 'a concurrent write waited behind the held lock')


    # ── Auditoría externa v0.12.0: una sola autoridad y evidencia calculada ──

    def test_pending_decision_or_ambiguity_never_starts(self):
        for extra in ({'decision': 'pending'}, {'clarity': 'ambiguous'}):
            with self.assertRaises(ValueError) as caught:
                self.call('alex', 'start', risk='low', files=['app.py'], acceptance='x', scope='local',
                          reuse='x', **{'decision': 'none', **extra})
            self.assertIn('Pending decisions', str(caught.exception))
        with self.assertRaises(ValueError):
            self.call('alex', 'status')

    def test_unready_project_or_missing_reuse_never_starts(self):
        with self.assertRaises(ValueError):
            self.call('alex', 'start', risk='low', files=['app.py'], acceptance='x', scope='local', decision='none')
        with closing(sqlite3.connect(self.db_path)) as db, db:
            db.execute("UPDATE schema_meta SET value='missing' WHERE key='project_readiness'")
        with self.assertRaises(ValueError) as caught:
            self.start()
        self.assertIn('DISCOVERY', str(caught.exception))

    def test_visual_needs_design_system_but_stays_trivial(self):
        with self.assertRaises(ValueError) as caught:
            self.call('alex', 'start', risk='low', files=['app.py'], acceptance='x', scope='local',
                      decision='none', reuse='x', visual=True)
        self.assertIn('sistema de diseño', str(caught.exception))
        with closing(sqlite3.connect(self.db_path)) as db, db:
            db.execute("INSERT INTO concepts(slug,title,body_md,updated_at) VALUES('design-system','DS','tokens',datetime('now'))")
        started = self.call('alex', 'start', risk='low', files=['app.py'], acceptance='x', scope='local',
                            decision='none', reuse='x', visual=True)
        self.assertEqual((started['risk'], started['route']), ('low', 'FAST-TRACK'))

    def test_trivial_route_is_alex_teo_with_configured_verification(self):
        self.configure(fast='ls {files}')
        started = self.start()
        self.assertEqual(started['auto_verify'], ['bash', '-c', 'ls app.py tests/check.test.sh'])
        (self.root / 'app.py').write_text('value = 1  # mayúscula corregida\n')
        delivered = self.call('teo', 'deliver')
        self.assertEqual(delivered['state'], 'verified')
        self.assertEqual(delivered['verification']['agent'], 'auto')
        completed = self.call('alex', 'complete')
        self.assertEqual(completed['state'], 'completed')
        with closing(sqlite3.connect(self.db_path)) as db, db:
            row = db.execute("SELECT agent, command, exit_code, tree_hash FROM receipts WHERE task_id='request'").fetchone()
            metric = db.execute("SELECT outcome FROM workflow_metrics WHERE request_id='request'").fetchone()
        self.assertEqual(row[:3], ('auto', 'skalling_workflow:complete', 0))
        self.assertEqual(row[3], completed['receipt_tree_hash'])
        self.assertEqual(metric[0], 'success')

    def test_unit_suite_is_not_started_automatically_without_fast_command(self):
        self.configure(unit='bash tests/check.test.sh')
        started = self.start()
        self.assertIsNone(started['auto_verify'])
        self.assertEqual(started['configured_verification'], ['bash', '-c', 'bash tests/check.test.sh'])
        (self.root / 'app.py').write_text('value = 1  # ajuste local\n')
        delivered = self.call('teo', 'deliver')
        self.assertEqual(delivered['state'], 'verification_ready')
        self.assertIsNone(delivered['auto_verify'])
        self.assertEqual(delivered['checks'], [])
        self.assertEqual(self.engine.next_action(delivered)['agent'], 'jhon')

    def test_trivial_route_failure_returns_to_teo(self):
        self.configure(fast='bash tests/check.test.sh')
        self.start()
        (self.root / 'app.py').write_text('value = 2\n')
        delivered = self.call('teo', 'deliver')
        self.assertEqual(delivered['state'], 'implementation_ready')
        self.assertEqual(delivered['verification']['exit_code'], 1)
        with self.assertRaises(ValueError):
            self.call('alex', 'complete')

    def test_generic_green_check_can_be_reviewed_against_the_actual_request(self):
        self.configure(fast='test -f app.py')
        self.start()
        (self.root / 'app.py').write_text('value = 2\n')
        auto = self.call('teo', 'deliver')
        self.assertEqual(auto['state'], 'verified')
        self.assertIn('oracle', auto['next_step'])
        self.assertNotEqual(auto['checks'][0]['criterion'], auto['acceptance'])
        with self.assertRaises(ValueError):
            self.call('teo', 'oracle', expected='one', negative='two', invariant='int', refutation='test value')
        reviewed = self.call('jhon', 'oracle', expected='one', negative='two', invariant='int', refutation='test value')
        self.assertEqual(reviewed['state'], 'verification_ready')
        self.assertEqual(len(reviewed['checks']), 1, 'Keep the valid generic check as evidence')
        self.assertIsNone(reviewed['auto_verify'])
        with self.assertRaises(ValueError):
            self.call('alex', 'complete')
        checked = self.call('jhon', 'check', argv=['bash', 'tests/check.test.sh'], method='behavior', criterion='value stays 1')
        self.assertEqual(checked['verification']['exit_code'], 1)
        self.call('jhon', 'reject', evidence='The file exists, but value is 2 instead of 1')
        (self.root / 'app.py').write_text('value = 1\n')
        self.assertEqual(self.call('teo', 'deliver')['state'], 'verification_ready')
        self.call('jhon', 'oracle', expected='one', negative='two', invariant='int', refutation='test value')
        self.call('jhon', 'check', argv=['bash', 'tests/check.test.sh'], method='behavior', criterion='value stays 1')
        self.call('jhon', 'approve', evidence='Observed the requested value one')
        self.assertEqual(self.call('alex', 'complete')['state'], 'completed')

    def test_verification_command_is_frozen_at_start(self):
        self.configure(fast='bash tests/check.test.sh')
        self.start()
        (self.root / 'app.py').write_text('value = 2\n')
        self.configure(fast='true')   # quien implementa no cambia qué se verifica
        self.assertEqual(self.call('teo', 'deliver')['state'], 'implementation_ready')

    def test_without_configured_command_trivial_goes_to_jhon(self):
        self.start()
        self.assertEqual(self.call('teo', 'deliver')['state'], 'verification_ready')

    def test_reclassification_supersedes_only_what_it_names(self):
        self.start()
        other = self.engine.operate({'project': str(self.root), 'actor': 'alex', 'session': 'b', 'action': 'start',
                                     'payload': {'id': 'other', 'risk': 'low', 'files': ['app.py'], 'acceptance': 'x',
                                                 'scope': 'local', 'decision': 'none', 'reuse': 'x', 'intent': 'Preserve value'}})
        self.assertEqual(other['state'], 'implementation_ready')
        self.assertEqual(self.call('alex', 'status')['state'], 'implementation_ready')
        self.engine.operate({'project': str(self.root), 'actor': 'alex', 'session': 'a', 'action': 'start',
                             'payload': {'id': 'request-2', 'risk': 'medium', 'files': ['app.py'], 'acceptance': 'x',
                                         'scope': 'local', 'decision': 'none', 'reuse': 'x', 'intent': 'Preserve value', 'supersedes': 'request'}})
        self.assertEqual(self.call('alex', 'status')['state'], 'superseded')
        with self.assertRaises(ValueError):
            self.call('teo', 'deliver')
        with closing(sqlite3.connect(self.db_path)) as db, db:
            outcomes = dict(db.execute("SELECT request_id, coalesce(outcome,'open') FROM workflow_metrics"))
        self.assertEqual(outcomes['request'], 'superseded')
        self.assertNotEqual(outcomes['other'], 'superseded')


    def test_plan_task_is_approved_with_the_verification_the_engine_recorded(self):
        with closing(sqlite3.connect(self.db_path)) as db, db:
            db.execute("INSERT INTO tasks(plan_id,slug,title,status) VALUES(?,'t1','Tarea','in_review')", (self.plan_id,))
        advance = lambda: subprocess.run(
            ['bash', str(ROOT / 'scripts/teamdb-claim.sh'), '--advance', 'plan', 't1', '--to=approved', str(self.root)],
            capture_output=True, text=True, env={**os.environ, 'SKALLING_RUNTIME_AGENT': 'jhon'})
        blocked = advance()
        self.assertNotEqual(blocked.returncode, 0)
        self.assertIn('skalling_workflow', blocked.stdout)
        self.call('alex', 'start', risk='medium', files=['app.py', 'tests/check.test.sh'], acceptance='value remains one',
                  scope='local', decision='none', reuse='app.py', task='plan/t1')
        self.call('sol', 'plan', evidence='diseño')
        self.call('sol', 'ready', evidence='listo', plan_id=self.plan_id)
        self.verify()
        approved = advance()
        self.assertEqual(approved.returncode, 0, approved.stdout + approved.stderr)
        with closing(sqlite3.connect(self.db_path)) as db, db:
            self.assertEqual(db.execute("SELECT status FROM tasks WHERE slug='t1'").fetchone()[0], 'approved')


    def test_booleans_and_files_are_parsed_strictly(self):
        # Prueba real con 2.0.18: un modelo mandó "visual": "false" (texto) y
        # bool("false") es True -> se exigía un sistema de diseño innecesario.
        started = self.call('alex', 'start', risk='low', files=['app.py'], acceptance='x', scope='local',
                            decision='none', reuse='x', visual='false', sensitive='false')
        self.assertEqual((started['risk'], started['visual']), ('low', False))
        with self.assertRaises(ValueError) as caught:
            self.engine.operate({'project': str(self.root), 'actor': 'alex', 'session': 's', 'action': 'start',
                                 'payload': {'id': 'x2', 'risk': 'low', 'files': {'item': ['app.py']}, 'acceptance': 'x',
                                             'scope': 'local', 'decision': 'none', 'reuse': 'x', 'intent': 'Preserve value'}})
        self.assertIn('lista JSON de rutas', str(caught.exception))
        with self.assertRaises(ValueError):
            self.engine.operate({'project': str(self.root), 'actor': 'alex', 'session': 's', 'action': 'start',
                                 'payload': {'id': 'x3', 'risk': 'low', 'files': ['app.py'], 'acceptance': 'x',
                                             'scope': 'local', 'decision': 'none', 'reuse': 'x', 'visual': 'quizás'}})


    def test_jhon_can_run_the_projects_configured_verification(self):
        # Prueba real con 2.0.18: Jhon no podía registrar ningún check porque el
        # comando del proyecto no estaba en su política y un plugin v2 no puede
        # pedir permiso. El comando declarado, congelado en start, sí corre.
        self.configure(unit='bash tests/check.test.sh')
        self.start('medium', execution_mode='staged')
        self.call('sol', 'plan', evidence='d')
        self.call('sol', 'ready', evidence='r', plan_id=self.plan_id)
        self.call('teo', 'deliver')
        self.call('jhon', 'oracle', expected='one', negative='two', invariant='int', refutation='t')
        self.configure(unit='true')  # editar project.yaml después no cambia qué se corre
        checked = self.call('jhon', 'check', configured=True, method='regresión', criterion='value stays 1')
        self.assertEqual(checked['verification']['argv'], ['bash', '-c', 'bash tests/check.test.sh'])
        self.assertEqual(checked['verification']['exit_code'], 0)
        self.assertEqual(self.call('jhon', 'approve', evidence='comando del proyecto cubre el criterio')['state'], 'verified')


    def test_growing_request_takes_the_new_route_and_its_evidence(self):
        # Auditoría de c7517ea (P1): low + rescope a otro módulo con sintaxis
        # inválida terminaba completed con verificador auto, sin Sol ni Jhon.
        (self.root / 'src').mkdir()
        (self.root / 'src/other.py').write_text('x = 1\n')
        subprocess.run(['git', '-C', str(self.root), 'add', '-A'], check=True)
        subprocess.run(['git', '-C', str(self.root), 'commit', '-q', '-m', 'add src'], check=True)
        self.configure(fast='ls {files}')
        self.start()
        (self.root / 'src/other.py').write_text('def broken(:\n')
        rescoped = self.call('teo', 'rescope', files=['src/other.py'], evidence='hacía falta tocar src/')
        self.assertEqual((rescoped['risk'], rescoped['state']), ('medium', 'clarified'))
        self.assertIsNone(rescoped['auto_verify'])
        for actor, action in (('teo', 'deliver'), ('alex', 'complete')):
            with self.assertRaises(ValueError):
                self.call(actor, action)
        self.call('sol', 'plan', evidence='plan para el alcance nuevo')
        self.call('sol', 'ready', evidence='listo', plan_id=self.plan_id)
        delivered = self.call('teo', 'deliver')
        self.assertEqual(delivered['state'], 'verification_ready', 'medium no se verifica solo')
        with self.assertRaises(ValueError):
            self.call('alex', 'complete')

    def test_same_risk_rescope_rebuilds_the_command_over_the_new_files(self):
        self.configure(fast='ls {files}')
        self.start()
        (self.root / 'tests/extra.test.sh').write_text('true\n')
        rescoped = self.call('teo', 'rescope', files=['tests/extra.test.sh'], evidence='test nuevo')
        self.assertEqual(rescoped['risk'], 'low')
        self.assertIn('tests/extra.test.sh', rescoped['auto_verify'][2])
        self.configure(fast='true')   # editar project.yaml no cambia la plantilla congelada
        again = self.call('teo', 'rescope', files=['app.py', 'tests/extra2.test.sh'], evidence='otro test')
        self.assertTrue(again['auto_verify'][2].startswith('ls '))


    # ── Auditoría de c7517ea (P2): límites de las verificaciones ──

    def configure_raw(self, text):
        (self.root / '.opencode/project.yaml').write_text(text)

    def ready_for_checks(self, timeout):
        self.configure_raw(f'testing:\n  timeout_seconds: {timeout}\n')
        self.start('medium', execution_mode='staged')
        self.call('sol', 'plan', evidence='d')
        self.call('sol', 'ready', evidence='r', plan_id=self.plan_id)
        self.call('teo', 'deliver')
        self.call('jhon', 'oracle', expected='one', negative='two', invariant='int', refutation='t')

    def test_timeout_comes_from_the_project_and_is_frozen(self):
        self.ready_for_checks(timeout=3)
        self.configure_raw('testing:\n  timeout_seconds: 1\n')   # editar después no lo cambia
        checked = self.call('jhon', 'check', argv=['bash', '-c', 'sleep 2; true'], method='m', criterion='c')
        self.assertEqual(checked['verification']['exit_code'], 0)

    def test_timed_out_check_is_cancelled_without_orphans_or_record(self):
        self.ready_for_checks(timeout=1)
        marker = 'sleep 57.31'
        with self.assertRaises(ValueError) as caught:
            self.call('jhon', 'check', argv=['bash', '-c', f'{marker} & {marker}; true'], method='m', criterion='c')
        self.assertIn('superó 1s', str(caught.exception))
        time.sleep(0.3)
        leftover = subprocess.run(['pgrep', '-f', marker], capture_output=True, text=True)
        self.assertEqual(leftover.stdout.strip(), '', 'quedaron procesos huérfanos')
        self.assertEqual(self.call('jhon', 'status')['checks'], [], 'un check vencido no se registra')
        ok = self.call('jhon', 'check', argv=['true'], method='m', criterion='c')
        self.assertEqual(ok['verification']['exit_code'], 0)

    def test_cancelling_the_engine_kills_the_running_verification(self):
        self.ready_for_checks(timeout=60)
        marker = 'sleep 58.73'
        request = {'project': str(self.root), 'actor': 'jhon', 'session': 'jhon-session', 'action': 'check',
                   'payload': {'id': 'request', 'argv': ['bash', '-c', f'{marker} & {marker}'], 'method': 'm', 'criterion': 'c'}}
        proc = subprocess.Popen([sys.executable, str(ROOT / 'scripts/skalling-workflow.py')], stdin=subprocess.PIPE,
                                stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True)
        proc.stdin.write(json.dumps(request)); proc.stdin.close()
        proc.stdin = None  # Python 3.12 communicate() otherwise flushes the closed pipe.
        for _ in range(50):
            if subprocess.run(['pgrep', '-f', marker], capture_output=True).stdout:
                break
            time.sleep(0.1)
        proc.terminate()                     # lo que hace el plugin al cancelar
        proc.communicate(timeout=10)         # espera y cierra stdout/stderr
        time.sleep(0.3)
        self.assertEqual(subprocess.run(['pgrep', '-f', marker], capture_output=True, text=True).stdout.strip(), '')


    def test_request_usage_is_captured_automatically_from_opencode(self):
        # Auditoría de c7517ea: el consumo dependía de eventos manuales. Al
        # completar, el motor suma tokens/costo de la sesión y sus subagentes.
        outside = tempfile.TemporaryDirectory()
        self.addCleanup(outside.cleanup)
        oc = Path(outside.name) / 'opencode.db'
        with closing(sqlite3.connect(oc)) as conn, conn:
            conn.execute('CREATE TABLE session_v2 (id TEXT PRIMARY KEY, parent_id TEXT)')
            conn.execute('CREATE TABLE session_message (id INTEGER PRIMARY KEY, session_id TEXT, type TEXT, time_created INTEGER, data TEXT)')
            conn.executemany('INSERT INTO session_v2 VALUES (?,?)', [('alex-session', None), ('teo-sub', 'alex-session'), ('otra', None)])
        os.environ['SKALLING_OPENCODE_DB'] = str(oc)
        self.addCleanup(os.environ.pop, 'SKALLING_OPENCODE_DB', None)
        self.configure(fast='ls {files}')
        self.start()

        def message(session, agent, tokens_in, tokens_out, cache, cost, when=None):
            data = {'agent': agent, 'cost': cost, 'tokens': {'input': tokens_in, 'output': tokens_out, 'reasoning': 0,
                                                            'cache': {'read': cache, 'write': 0}}}
            with closing(sqlite3.connect(oc)) as conn, conn:
                conn.execute('INSERT INTO session_message(session_id,type,time_created,data) VALUES (?,?,?,?)',
                             (session, 'assistant', int((when or time.time()) * 1000), json.dumps(data)))
        message('alex-session', 'Alex', 1000, 100, 5000, 0.01)
        message('teo-sub', 'Teo', 2000, 300, 7000, 0.02)
        message('otra', 'Alex', 99999, 9999, 0, 9.0)                    # otra sesión: no cuenta
        message('alex-session', 'Alex', 55555, 5555, 0, 5.0, when=1.0)  # fuera de la ventana: no cuenta
        (self.root / 'app.py').write_text('value = 1  # ok\n')
        self.call('teo', 'deliver')
        completed = self.call('alex', 'complete')
        self.assertEqual(completed['usage']['tokens_input'], 3000)
        self.assertEqual(completed['usage']['agents'], ['Alex', 'Teo'])
        with closing(sqlite3.connect(self.db_path)) as db, db:
            row = db.execute("SELECT tokens_input, tokens_output, tokens_cache_read, cost, agents_used, retries "
                             "FROM workflow_metrics WHERE request_id='request'").fetchone()
        self.assertEqual(row, (3000, 400, 12000, 0.03, 'Alex,Teo', 0))

    def test_handoff_context_is_automatic_and_not_shared_between_agents(self):
        started = self.start()
        self.assertIn('context', self.engine.public_response(started))
        item = started['context']['concepts'][0]
        own = self.call('alex', 'status', context_seen=[item['read_key']])
        self.assertTrue(own['context']['concepts'][0]['already_read'])
        teo = self.call('teo', 'status')
        self.assertEqual(teo['context']['concepts'][0]['body'], 'App de prueba')
        with sqlite3.connect(self.db_path) as db:
            self.assertGreater(db.execute("SELECT context_bytes FROM workflow_metrics WHERE request_id='request'").fetchone()[0], 0)
            # Retrieval never steals ownership or counts a status as a handoff.
            state = json.loads(db.execute("SELECT body FROM agent_workflows WHERE id='request'").fetchone()[0])
            self.assertEqual(state['handoffs'], 0)

    def test_usage_resumed_session_is_counted_without_double_counting_children(self):
        runtime = self.root / 'runtime.db'
        with sqlite3.connect(runtime) as db:
            db.executescript('CREATE TABLE session_v2(id TEXT PRIMARY KEY,parent_id TEXT);'
                             'CREATE TABLE session_message(id INTEGER PRIMARY KEY,session_id TEXT,type TEXT,time_created INTEGER,data TEXT);')
            db.executemany('INSERT INTO session_v2 VALUES(?,?)', [('alex-session', None), ('resumed', None), ('child', 'resumed')])
        from unittest.mock import patch
        with patch.dict(os.environ, {'SKALLING_OPENCODE_DB': str(runtime)}):
            self.start()
            request = dict(project=str(self.root), actor='alex', session='resumed', action='status', payload={'id':'request'})
            self.engine.operate(request)
            child = {**request, 'actor':'teo', 'session':'child'}
            self.engine.operate(child)
            with sqlite3.connect(runtime) as db:
                data = json.dumps({'agent':'Teo', 'tokens':{'input':50,'output':10}})
                db.execute("INSERT INTO session_message VALUES(1,'child','assistant',?,?)", (int(time.time()*1000), data))
                db.execute("INSERT INTO session_message VALUES(2,'resumed','assistant',1,?)", (data,))
            state = self.engine.operate(request)
            self.assertEqual(state['usage']['tokens_input'], 50)
            self.assertEqual(state['usage']['tokens_output'], 10)

    def test_missing_opencode_database_never_breaks_completion(self):
        os.environ['SKALLING_OPENCODE_DB'] = str(self.root / 'no-existe.db')
        self.addCleanup(os.environ.pop, 'SKALLING_OPENCODE_DB', None)
        self.configure(fast='ls {files}')
        self.start()
        (self.root / 'app.py').write_text('value = 1  # ok\n')
        self.call('teo', 'deliver')
        self.assertEqual(self.call('alex', 'complete')['state'], 'completed')


if __name__ == '__main__': unittest.main()
