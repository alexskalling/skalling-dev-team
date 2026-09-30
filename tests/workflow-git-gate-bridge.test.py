"""Proves the two approval flows are actually unified: a workflow the new
engine marks 'completed' must satisfy the real git-gate.py pre-commit check
(the same function that decides whether `git commit` is allowed), not a
mock of it. This is the fix for the audit finding that finishing the new
engine's workflow never produced a receipt git-gate.py could see."""
import importlib.util
import os
from contextlib import closing
import sqlite3
import subprocess
import sys
import tempfile
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]


def load(name, relpath):
    # dont_write_bytecode: importing scripts/hooks/git-gate.py this way would
    # otherwise leave scripts/hooks/__pycache__/ behind, which trips up
    # install-global.sh's plain `cp` of that directory in other tests.
    previous = sys.dont_write_bytecode
    sys.dont_write_bytecode = True
    try:
        spec = importlib.util.spec_from_file_location(name, ROOT / relpath)
        module = importlib.util.module_from_spec(spec)
        spec.loader.exec_module(module)
        return module
    finally:
        sys.dont_write_bytecode = previous
    return module


class WorkflowSealsGitGateReceipt(unittest.TestCase):
    def setUp(self):
        self.workflow = load('workflow_under_test', 'scripts/skalling-workflow.py')
        self.gitgate = load('gitgate_under_test', 'scripts/hooks/git-gate.py')
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
        # Real project init (schema_meta, receipts.tree_hash, agent_workflows all
        # come from here), not a hand-rolled partial schema.
        subprocess.run(['bash', str(ROOT / 'scripts/teamdb-init.sh'), str(self.root)],
                        capture_output=True, check=True)
        with closing(sqlite3.connect(self.root / '.opencode/context/team.db')) as db, db:
            db.execute("INSERT OR REPLACE INTO schema_meta(key,value) VALUES('project_readiness','initialized')")
            db.execute("INSERT INTO concepts(slug,title,body_md,updated_at) VALUES('project-summary','R','App',datetime('now'))")
        self.cwd = os.getcwd()
        os.chdir(self.root)
        self.addCleanup(os.chdir, self.cwd)

    def call(self, actor, action, **payload):
        if action == 'start':
            payload.setdefault('intent', 'Preserve the declared fixture value')
        if action in {'approve', 'complete'}:
            payload.setdefault('coverage', [{'outcome_id': 'acceptance', 'check_index': 0,
                                            'observation': 'Fixture value assertion passed'}])
        return self.workflow.operate({'project': str(self.root), 'actor': actor, 'session': actor + '-session',
                                       'action': action, 'payload': {'id': 'request', **payload}})

    def test_completed_workflow_satisfies_real_git_gate_pre_commit(self):
        self.call('alex', 'start', risk='low', files=['app.py', 'tests/check.test.sh'],
                  acceptance='value remains one', scope='local', decision='none', reuse='app.py')
        self.call('teo', 'deliver')
        self.call('jhon', 'oracle', expected='one', negative='two', invariant='integer', refutation='test')
        self.call('jhon', 'check', argv=['bash', 'tests/check.test.sh'], method='falsification', criterion='value stays 1')
        self.call('jhon', 'approve', evidence='falsification covers the declared criterion')
        self.assertEqual(self.call('alex', 'complete')['state'], 'completed')

        db = sqlite3.connect((self.root / '.opencode/context/team.db').as_uri() + '?mode=ro', uri=True)
        self.addCleanup(db.close)
        self.gitgate.check(['--cached'], db, 'pre-commit')  # raises ValueError if git-gate would block

    def test_staged_file_outside_reviewed_scope_is_not_approved(self):
        """Auditoría A04: un .opencode/unreviewed.py staged antes del flujo
        quedaba cubierto por el receipt aunque solo se revisó app.py."""
        (self.root / '.opencode/unreviewed.py').write_text('def broken(:\n')
        subprocess.run(['git', 'add', '--', '.opencode/unreviewed.py'], cwd=self.root, check=True)
        self.call('alex', 'start', risk='low', files=['app.py', 'tests/check.test.sh'],
                  acceptance='value remains one', scope='local', decision='none', reuse='app.py')
        self.call('teo', 'deliver')
        self.call('jhon', 'oracle', expected='one', negative='two', invariant='integer', refutation='test')
        self.call('jhon', 'check', argv=['bash', 'tests/check.test.sh'], method='falsification', criterion='value stays 1')
        self.call('jhon', 'approve', evidence='falsification covers the declared criterion')
        before = subprocess.check_output(['git', 'ls-files', '--stage', '-z'], cwd=self.root)
        completed = self.call('alex', 'complete')
        self.assertEqual(completed['state'], 'completed')
        self.assertTrue(completed['receipt_tree_hash'])
        self.assertEqual(before, subprocess.check_output(['git', 'ls-files', '--stage', '-z'], cwd=self.root))
        db = sqlite3.connect((self.root / '.opencode/context/team.db').as_uri() + '?mode=ro', uri=True)
        self.addCleanup(db.close)
        # The isolated receipt must NEVER authorize the unrelated real index.
        with self.assertRaises(ValueError):
            self.gitgate.check(['--cached'], db, 'pre-commit')
        subprocess.run(['git', 'add', '--', 'app.py', 'tests/check.test.sh'], cwd=self.root, check=True)
        with self.assertRaises(ValueError):
            self.gitgate.check(['--cached'], db, 'pre-commit')
        # The very same receipt authorizes exactly the declared files, proving
        # completion did not bless the unreviewed tooling along with them.
        subprocess.run(['git', 'rm', '-q', '--cached', '--', '.opencode/unreviewed.py'], cwd=self.root, check=True)
        self.gitgate.check(['--cached'], db, 'pre-commit')

    def test_uncompleted_workflow_still_blocks_git_gate(self):
        self.call('alex', 'start', risk='low', files=['app.py', 'tests/check.test.sh'],
                  acceptance='value remains one', scope='local', decision='none', reuse='app.py')
        self.call('teo', 'deliver')
        subprocess.run(['git', 'add', '--', 'app.py', 'tests/check.test.sh'], cwd=self.root, check=True)

        db = sqlite3.connect((self.root / '.opencode/context/team.db').as_uri() + '?mode=ro', uri=True)
        self.addCleanup(db.close)
        with self.assertRaises(ValueError):
            self.gitgate.check(['--cached'], db, 'pre-commit')

    def test_trivial_route_auto_verification_satisfies_git_gate(self):
        (self.root / '.opencode/project.yaml').write_text(
            'testing:\n  fast:\n    available: true\n    command: "bash tests/check.test.sh"\n')
        self.call('alex', 'start', risk='low', files=['app.py', 'tests/check.test.sh'],
                  acceptance='value remains one', scope='local', decision='none', reuse='app.py')
        (self.root / 'tests/check.test.sh').write_text('test "$(cat app.py)" = "value = 1"  # revisado\n')
        self.assertEqual(self.call('teo', 'deliver')['state'], 'verified')
        self.assertEqual(self.call('alex', 'complete')['state'], 'completed')
        db = sqlite3.connect((self.root / '.opencode/context/team.db').as_uri() + '?mode=ro', uri=True)
        self.addCleanup(db.close)
        self.gitgate.check(['--cached'], db, 'pre-commit')

    def test_hand_made_receipts_without_evidence_do_not_open_the_gate(self):
        # Auditoría externa v0.12.0 #2: un receipt de Luz 'review-seal' con
        # resumen vacío abría el commit. Solo cuenta evidencia calculada.
        (self.root / 'app.py').write_text('def broken(:\n')
        subprocess.run(['git', 'add', '--', 'app.py'], cwd=self.root, check=True)
        diff = subprocess.run(['git', 'diff', '--cached', '--', '.', ':(exclude)db/teamdb/team.dump.sql'],
                              cwd=self.root, capture_output=True, check=True).stdout.rstrip(b'\n')
        import hashlib
        digest = hashlib.sha256(diff).hexdigest()[:16]
        with closing(sqlite3.connect(self.root / '.opencode/context/team.db')) as db, db:
            for agent, command in (('luz', 'review-seal'), ('jhon', 'manual'), ('auto', 'review --lens risk'),
                                   ('teo', 'skalling_workflow:complete')):
                db.execute("INSERT INTO receipts(id,task_id,agent,command,exit_code,output_summary,ts,tree_hash) "
                           "VALUES(?,?,?,?,0,'',datetime('now'),?)", (agent + command, 't', agent, command, digest))
        db = sqlite3.connect((self.root / '.opencode/context/team.db').as_uri() + '?mode=ro', uri=True)
        self.addCleanup(db.close)
        with self.assertRaises(ValueError):
            self.gitgate.check(['--cached'], db, 'pre-commit')


if __name__ == '__main__':
    unittest.main()
