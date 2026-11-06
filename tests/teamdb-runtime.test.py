"""Connection invariants, migration recovery, telemetry isolation and direct focus."""
from contextlib import closing
import importlib.util
import json
from pathlib import Path
import sqlite3
import sys
import tempfile
import unittest
from unittest.mock import patch

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT / 'scripts'))
from skalling_db import connect
from teamdb_guard import connect as guarded_connect


def load(name, path):
    spec = importlib.util.spec_from_file_location(name, path)
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


base = load('workflow_tests', ROOT / 'tests/workflow-engine.test.py')
migration = load('projection', ROOT / 'sql/migrations/066_workflow_projection.py')


class Connections(unittest.TestCase):
    def test_runtime_and_guard_enforce_foreign_keys(self):
        for factory in (connect, guarded_connect):
            with self.subTest(factory=factory), closing(factory(':memory:')) as db:
                db.execute('CREATE TABLE parents(id INTEGER PRIMARY KEY)')
                db.execute('CREATE TABLE children(parent INTEGER REFERENCES parents(id))')
                with self.assertRaises(sqlite3.IntegrityError):
                    db.execute('INSERT INTO children VALUES(999)')

    def test_reads_cannot_create_or_modify_database_with_uri_characters(self):
        with tempfile.TemporaryDirectory() as tmp:
            path = Path(tmp) / 'team?#.db'
            for readonly in (True, False):
                with self.assertRaises(sqlite3.OperationalError):
                    connect(path, readonly=readonly)
                self.assertFalse(path.exists())
            with closing(connect(path, create=True)) as db:
                db.execute('CREATE TABLE data(value TEXT)')
                db.commit()
            with closing(connect(path, readonly=True)) as db:
                self.assertEqual(db.execute('PRAGMA query_only').fetchone()[0], 1)
                with self.assertRaises(sqlite3.OperationalError):
                    db.execute("INSERT INTO data VALUES('changed')")

    def test_projection_migration_preserves_history_and_is_repeatable(self):
        with tempfile.TemporaryDirectory() as tmp:
            path = Path(tmp) / 'team.db'
            body = json.dumps(dict(state='verified', project_directory='/repo', start_session='s',
                                   updated_at=3.5, constraints=['SQLite'], checks=[{'output':'evidence'}]))
            with closing(connect(path, create=True)) as db, db:
                db.executescript('CREATE TABLE agent_workflows(id TEXT PRIMARY KEY,body TEXT NOT NULL);'
                                 'CREATE TABLE agent_workflow_events(request_id TEXT,session TEXT,ts REAL);')
                db.execute('INSERT INTO agent_workflows VALUES(?,?)', ('one', body))
                db.execute("INSERT INTO agent_workflow_events VALUES('one','s',1)")
            migration.migrate(path)
            migration.migrate(path)
            with closing(connect(path)) as db, db:
                self.assertEqual(db.execute('SELECT body FROM agent_workflows').fetchone()[0], body)
                self.assertEqual(db.execute('SELECT workflow_state,project_directory,start_session,state_revision '
                                            'FROM agent_workflows').fetchone(), ('verified','/repo','s',3.5))
                self.assertEqual(db.execute('SELECT count(*) FROM agent_workflow_events').fetchone()[0], 1)
                plan = db.execute("EXPLAIN QUERY PLAN SELECT id FROM agent_workflows WHERE project_directory=? AND start_session=?",
                                  ('/repo','s')).fetchall()
                self.assertIn('idx_workflow_project_session', str(plan))
                db.execute("UPDATE agent_workflows SET body=json_set(body,'$.state','completed')")
                self.assertEqual(db.execute('SELECT workflow_state FROM agent_workflows').fetchone()[0], 'completed')

    def test_corrupt_json_rolls_back_projection_migration(self):
        with tempfile.TemporaryDirectory() as tmp:
            path = Path(tmp) / 'team.db'
            with closing(connect(path, create=True)) as db, db:
                db.executescript("CREATE TABLE agent_workflows(id TEXT,body TEXT);"
                                 "CREATE TABLE agent_workflow_events(request_id TEXT,session TEXT,ts REAL);"
                                 "INSERT INTO agent_workflows VALUES('broken','not json');")
            with self.assertRaises(sqlite3.DatabaseError):
                migration.migrate(path)
            with closing(connect(path)) as db:
                self.assertEqual([r[1] for r in db.execute('PRAGMA table_xinfo(agent_workflows)')], ['id','body'])
                self.assertEqual(db.execute('SELECT body FROM agent_workflows').fetchone()[0], 'not json')


class WorkflowInfrastructure(base.Workflow):
    def test_telemetry_runs_after_commit_and_never_enters_state_json(self):
        self.start()
        usage = dict(tokens_input=10, tokens_output=2, tokens_cache_read=0, cost=.01, agents=['Teo'])
        def collect(*args):
            with closing(connect(self.db_path, timeout=.1)) as db, db:
                db.execute('BEGIN IMMEDIATE')
                self.assertEqual(json.loads(db.execute("SELECT body FROM agent_workflows WHERE id='request'").fetchone()[0])['state'], 'completed')
            return usage
        with patch.object(self.engine, 'runtime_usage', side_effect=collect) as counter:
            self.verify()
            counter.assert_not_called()
            completed = self.call('alex','complete')
            counter.assert_called_once()
        self.assertEqual(completed['usage'], usage)
        with closing(connect(self.db_path)) as db:
            state = json.loads(db.execute("SELECT body FROM agent_workflows WHERE id='request'").fetchone()[0])
            self.assertNotIn('usage', state)
            self.assertEqual(db.execute('SELECT tokens_input FROM workflow_metrics').fetchone()[0], 10)
        self.assertEqual(self.call('alex','status')['usage']['tokens_input'], 10)

    def test_unavailable_telemetry_does_not_undo_completion(self):
        self.start(); self.verify()
        with patch.object(self.engine,'runtime_usage',side_effect=ValueError('malformed runtime telemetry')):
            self.assertEqual(self.call('alex','complete')['state'], 'completed')
        self.assertEqual(self.call('alex','status')['state'], 'completed')

    def test_late_metrics_cannot_overwrite_a_newer_revision(self):
        self.start(); self.verify()
        def collect(*args):
            with closing(connect(self.db_path)) as db, db:
                db.execute("UPDATE agent_workflows SET body=json_set(body,'$.updated_at',99999999999)")
                db.execute('UPDATE workflow_metrics SET tokens_input=77')
            return dict(tokens_input=10,tokens_output=2,tokens_cache_read=0,cost=0,agents=[])
        with patch.object(self.engine,'runtime_usage',side_effect=collect):
            self.call('alex','complete')
        with closing(connect(self.db_path)) as db:
            self.assertEqual(db.execute('SELECT tokens_input FROM workflow_metrics').fetchone()[0], 77)
            self.assertEqual(db.execute('SELECT state_revision FROM agent_workflows').fetchone()[0], 99999999999)

    def test_broken_optional_retrieval_does_not_hide_the_active_request(self):
        with patch('skalling_context.request_context',side_effect=sqlite3.OperationalError('unavailable index')):
            state = self.call('alex','start',risk='low',scope='local',files=['app.py'],acceptance='one',reuse='app',
                              constraints=['Preserve SQLite'])
        self.assertEqual(state['constraints'], ['Preserve SQLite'])
        self.assertEqual(state['context']['freshness']['status'], 'unavailable')
        self.assertEqual(state['state'], 'implementation_ready')

    def test_local_high_risk_keeps_both_reviewers_without_routine_planning(self):
        started = self.call('alex','start',risk='high',scope='local',sensitive=True,
                            files=['app.py','tests/check.test.sh'],acceptance='one',reuse='app')
        self.assertEqual(started['execution_mode'], 'direct')
        self.assertEqual(started['agents'], 'Alex → Teo → Jhon → Luz')
        self.verify()
        with self.assertRaises(ValueError):
            self.call('alex','complete')
        self.call('luz','check',argv=['bash','tests/check.test.sh'],method='risk',criterion='one')
        self.call('luz','approve',evidence='risk checked',findings='No risk regression')
        self.assertEqual(self.call('alex','complete')['state'], 'completed')

    def test_unrelated_rejection_is_atomic_and_optional_notes_do_not_block(self):
        self.start(); self.call('teo','deliver')
        before = self.call('alex','status')
        request = dict(project=str(self.root),actor='jhon',session='review',action='reject',
                       payload={'id':'request','evidence':'Prefer another style',
                                'findings':[{'id':'style','problem':'Name too short','expected':'Longer name'}]})
        with self.assertRaisesRegex(ValueError,'outcome_id'):
            self.engine.operate(request)
        after = self.call('alex','status')
        for key in ('state','digest','delivery_number','rejection_count','checks'):
            self.assertEqual(after[key], before[key])
        deferred = self.call('jhon','defer',note_id='style',suggestion='Longer name',reason='Optional preference')
        self.assertEqual(deferred['state'], 'verification_ready')
        request['payload']['findings'][0].update(risk='Potential data exposure',files=['outside.py'])
        with self.assertRaisesRegex(ValueError,'alcance'):
            self.engine.operate(request)
        request['payload']['findings'][0]['files'] = ['app.py']
        self.assertEqual(self.engine.operate(request)['state'], 'implementation_ready')

    def test_dependency_scans_release_writer_and_detect_concurrent_revision(self):
        self.start(); self.call('teo','deliver')
        self.call('jhon','oracle',expected='one',negative='two',invariant='integer',refutation='assert')
        def scan(root):
            with closing(connect(self.db_path,timeout=.1)) as db, db:
                db.execute('BEGIN IMMEDIATE')
            return 'stable-dependencies'
        with patch.object(self.engine,'evidence_context',side_effect=scan) as scanner:
            self.call('jhon','check',argv=['bash','tests/check.test.sh'],method='behavior',criterion='one',reusable=True)
            self.assertEqual(scanner.call_count,2)
        def change(root):
            with closing(connect(self.db_path)) as db, db:
                db.execute("UPDATE agent_workflows SET body=json_set(body,'$.updated_at',99999999999)")
            return 'stable-dependencies'
        with patch.object(self.engine,'evidence_context',side_effect=change):
            with self.assertRaisesRegex(ValueError,'changed during evidence scan'):
                self.call('jhon','check',argv=['true'],method='behavior',criterion='one',reusable=True)
        self.assertEqual(len(self.call('alex','status')['checks']),1)

    def test_explicit_check_budget_stops_new_tests_but_allows_verified_completion(self):
        self.call('alex','start',risk='low',scope='local',files=['app.py','tests/check.test.sh'],
                  acceptance='one',reuse='app',resource_budget={'max_checks':1})
        self.verify()
        state = self.call('alex','status')
        self.assertEqual(state['execution_budget']['checks_started'],1)
        self.assertEqual(state['execution_budget']['exhausted'],['max_checks'])
        self.assertEqual(self.call('alex','complete')['state'],'completed')

    def test_budget_inheritance_prevents_resetting_checks_by_superseding(self):
        common = dict(risk='low',scope='local',files=['app.py','tests/check.test.sh'],acceptance='one',reuse='app')
        self.configure(fast='bash tests/check.test.sh')
        self.call('alex','start',resource_budget={'max_checks':1},**common)
        self.call('teo','probe')
        self.call('alex','start',id='next',supersedes='request',**common)
        with self.assertRaisesRegex(ValueError,'Presupuesto'):
            self.call('teo','probe',id='next')
        state = self.call('alex','status',id='next')
        self.assertEqual(state['execution_budget']['checks_started'],1)
        with self.assertRaisesRegex(ValueError,'focus_revision'):
            self.call('alex','start',id='third',supersedes='next',resource_budget={'max_checks':2},**common)

    def test_unset_budget_is_not_invented_and_invalid_budget_is_rejected(self):
        common = dict(risk='low',scope='local',files=['app.py'],acceptance='one',reuse='app')
        for invalid in ({}, {'max_checks':True}, {'max_tokens':1000}, {'max_elapsed_seconds':0}):
            with self.assertRaises(ValueError):
                self.call('alex','start',resource_budget=invalid,**common)
        self.call('alex','start',**common)
        self.assertNotIn('resource_budget',self.call('alex','status'))

    def test_rescope_requires_a_named_result_and_does_not_mutate_on_failure(self):
        self.start()
        request = dict(project=str(self.root),actor='teo',session='implementation',action='rescope',
                       payload={'id':'request','files':['extra.py'],'evidence':'Optional feature'})
        with self.assertRaisesRegex(ValueError,'outcome_id'):
            self.engine.operate(request)
        self.assertNotIn('extra.py',self.call('alex','status')['files'])

    def test_elapsed_budget_prevents_execution_without_discarding_state(self):
        self.configure(fast='bash tests/check.test.sh')
        self.call('alex','start',risk='low',scope='local',files=['app.py'],acceptance='one',reuse='app',
                  resource_budget={'max_elapsed_seconds':1})
        with closing(connect(self.db_path)) as db, db:
            db.execute("UPDATE agent_workflows SET body=json_set(body,'$.budget_started_at',0)")
        with patch.object(self.engine,'run_bounded') as command:
            with self.assertRaisesRegex(ValueError,'max_elapsed_seconds'):
                self.call('teo','deliver')
            command.assert_not_called()
        state = self.call('alex','status')
        self.assertEqual(state['state'],'implementation_ready')
        self.assertEqual(state['delivery_number'],0)

    def test_request_limits_survive_empty_retrieval_and_seen_context(self):
        self.call('alex','start',risk='low',scope='local',files=['app.py'],acceptance='one',reuse='app',
                  constraints=['Use SQLite only'],non_goals=['No publication'],commit_policy='forbidden')
        with patch('skalling_context.request_context',return_value={'concepts':[], 'omitted':[]}):
            state = self.engine.public_response(self.call('alex','status',context_seen=[]))
        self.assertEqual(state['constraints'], ['Use SQLite only'])
        self.assertEqual(state['non_goals'], ['No publication'])
        self.assertEqual(state['commit_policy'], 'forbidden')
        self.assertEqual(state['context']['concepts'], [])


def load_tests(loader, tests, pattern):
    suite = loader.loadTestsFromTestCase(Connections)
    suite.addTests(WorkflowInfrastructure(name) for name in WorkflowInfrastructure.__dict__ if name.startswith('test_'))
    return suite


if __name__ == '__main__':
    unittest.main()
