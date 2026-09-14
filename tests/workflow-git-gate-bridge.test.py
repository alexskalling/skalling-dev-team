"""Proves the two approval flows are actually unified: a workflow the new
engine marks 'completed' must satisfy the real git-gate.py pre-commit check
(the same function that decides whether `git commit` is allowed), not a
mock of it. This is the fix for the audit finding that finishing the new
engine's workflow never produced a receipt git-gate.py could see."""
import importlib.util
import os
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
        self.cwd = os.getcwd()
        os.chdir(self.root)
        self.addCleanup(os.chdir, self.cwd)

    def call(self, actor, action, **payload):
        return self.workflow.operate({'project': str(self.root), 'actor': actor, 'session': actor + '-session',
                                       'action': action, 'payload': {'id': 'request', **payload}})

    def test_completed_workflow_satisfies_real_git_gate_pre_commit(self):
        self.call('alex', 'start', risk='low', files=['app.py', 'tests/check.test.sh'],
                  acceptance='value remains one', scope='local', decision='none')
        self.call('teo', 'deliver')
        self.call('jhon', 'oracle', expected='one', negative='two', invariant='integer', refutation='test')
        self.call('jhon', 'check', argv=['bash', 'tests/check.test.sh'], method='falsification', criterion='value stays 1')
        self.call('jhon', 'approve', evidence='falsification covers the declared criterion')
        self.assertEqual(self.call('alex', 'complete')['state'], 'completed')

        db = sqlite3.connect((self.root / '.opencode/context/team.db').as_uri() + '?mode=ro', uri=True)
        self.addCleanup(db.close)
        self.gitgate.check(['--cached'], db, 'pre-commit')  # raises ValueError if git-gate would block

    def test_uncompleted_workflow_still_blocks_git_gate(self):
        self.call('alex', 'start', risk='low', files=['app.py', 'tests/check.test.sh'],
                  acceptance='value remains one', scope='local', decision='none')
        self.call('teo', 'deliver')
        subprocess.run(['git', 'add', '--', 'app.py', 'tests/check.test.sh'], cwd=self.root, check=True)

        db = sqlite3.connect((self.root / '.opencode/context/team.db').as_uri() + '?mode=ro', uri=True)
        self.addCleanup(db.close)
        with self.assertRaises(ValueError):
            self.gitgate.check(['--cached'], db, 'pre-commit')


if __name__ == '__main__':
    unittest.main()
