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

    def configure(self, **commands):
        lines = ['testing:']
        for name, command in commands.items():
            lines += [f'  {name}:', '    available: true', f'    command: "{command}"']
        (self.root / '.opencode/project.yaml').write_text('\n'.join(lines) + '\n')

    def call(self, actor, action, **payload):
        return self.engine.operate({'project': str(self.root), 'actor': actor, 'session': actor+'-session',
                                    'action': action, 'payload': {'id': 'request', **payload}})

    def start(self, risk='low'):
        return self.call('alex', 'start', risk=risk, files=['app.py', 'tests/check.test.sh'],
                         acceptance='value remains one', scope='local', decision='none', reuse='app.py existente')

    def verify(self):
        self.call('teo', 'deliver')
        self.call('jhon', 'oracle', expected='value one', negative='value two', invariant='integer', refutation='test value')
        self.call('jhon', 'check', argv=['bash', 'tests/check.test.sh'], method='falsification', criterion='value stays 1')
        return self.call('jhon', 'approve', evidence='falsification check covers the declared acceptance criterion')

    def test_medium_route_reaches_implementation_with_real_plan_helpers(self):
        # Caso real (sesión 2026-09-28): Sol mandó ready con plan_id 1 (el
        # número del ejemplo de su prompt) y el equipo creyó que no había
        # transición de planned a implementation_ready. Los demás tests
        # insertan el plan directo en la base; este usa los helpers reales.
        scripts = ROOT / 'scripts'
        env = {k: v for k, v in os.environ.items() if not k.startswith(('SKALLING_', 'TEAMDB_'))}
        self.assertEqual(self.start(risk='medium')['state'], 'clarified')
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
        ready = self.call('sol', 'ready', evidence='plan aprobado', plan_id=plan_id)
        self.assertEqual(ready['state'], 'implementation_ready')
        self.assertIn('Teo', ready['next_step'])

    def test_rejection_says_state_and_who_acts_next(self):
        self.start(risk='medium')
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
        with self.assertRaises(ValueError):
            self.call('teo', 'rescope', files=['extra.py'], evidence='')

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
                             'files': ['app.py'], 'acceptance': 'x', 'scope': 'local', 'decision': 'none',
                             'reuse': 'x'}})
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

    def test_trivial_route_failure_returns_to_teo(self):
        self.configure(fast='bash tests/check.test.sh')
        self.start()
        (self.root / 'app.py').write_text('value = 2\n')
        delivered = self.call('teo', 'deliver')
        self.assertEqual(delivered['state'], 'implementation_ready')
        self.assertEqual(delivered['verification']['exit_code'], 1)
        with self.assertRaises(ValueError):
            self.call('alex', 'complete')

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
                                                 'scope': 'local', 'decision': 'none', 'reuse': 'x'}})
        self.assertEqual(other['state'], 'implementation_ready')
        self.assertEqual(self.call('alex', 'status')['state'], 'implementation_ready')
        self.engine.operate({'project': str(self.root), 'actor': 'alex', 'session': 'a', 'action': 'start',
                             'payload': {'id': 'request-2', 'risk': 'medium', 'files': ['app.py'], 'acceptance': 'x',
                                         'scope': 'local', 'decision': 'none', 'reuse': 'x', 'supersedes': 'request'}})
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
                                             'scope': 'local', 'decision': 'none', 'reuse': 'x'}})
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
        self.start('medium')
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
        self.start('medium')
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

    def test_missing_opencode_database_never_breaks_completion(self):
        os.environ['SKALLING_OPENCODE_DB'] = str(self.root / 'no-existe.db')
        self.addCleanup(os.environ.pop, 'SKALLING_OPENCODE_DB', None)
        self.configure(fast='ls {files}')
        self.start()
        (self.root / 'app.py').write_text('value = 1  # ok\n')
        self.call('teo', 'deliver')
        self.assertEqual(self.call('alex', 'complete')['state'], 'completed')


if __name__ == '__main__': unittest.main()
