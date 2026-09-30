"""Un workflow completo desde un git worktree usa la memoria del repositorio
principal y verifica los archivos del worktree.

Auditoría de c7517ea (P1): el motor buscaba .opencode/context/team.db dentro
del worktree (los helpers resolvían la del repositorio principal). Iniciar un
workflow fallaba con "agent_workflows falta y teamdb-init.sh no pudo migrarla"
y dejaba creada una base vacía. Lo mismo pasaba con teamdb-read, teamdb-memory
y otros helpers que armaban la ruta a mano.
"""
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
ENV = {**os.environ, 'SKALLING_ROOT': str(ROOT), 'GIT_AUTHOR_NAME': 't', 'GIT_AUTHOR_EMAIL': 't@t',
       'GIT_COMMITTER_NAME': 't', 'GIT_COMMITTER_EMAIL': 't@t'}
ENV.pop('SKALLING_RUNTIME_AGENT', None)


def load(name, relpath):
    previous, sys.dont_write_bytecode = sys.dont_write_bytecode, True
    try:
        spec = importlib.util.spec_from_file_location(name, ROOT / relpath)
        module = importlib.util.module_from_spec(spec)
        spec.loader.exec_module(module)
        return module
    finally:
        sys.dont_write_bytecode = previous


class WorkflowFromWorktree(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory()
        self.addCleanup(self.tmp.cleanup)
        self.main = Path(self.tmp.name) / 'repo'
        self.main.mkdir()
        self.git(self.main, 'init', '-q', '-b', 'main')
        (self.main / 'app.py').write_text('value = 1\n')
        (self.main / '.gitignore').write_text('.opencode/\n__pycache__/\n')
        self.git(self.main, 'add', '-A')
        self.git(self.main, 'commit', '-qm', 'init')
        subprocess.run(['bash', str(ROOT / 'scripts/teamdb-init.sh'), str(self.main)], env=ENV, capture_output=True, check=True)
        self.db = self.main / '.opencode/context/team.db'
        with closing(sqlite3.connect(self.db)) as conn, conn:
            conn.execute("INSERT OR REPLACE INTO schema_meta(key,value) VALUES('project_readiness','initialized')")
            conn.execute("INSERT INTO concepts(slug,title,body_md,updated_at) VALUES('project-summary','R','App',datetime('now'))")
        (self.main / '.opencode/project.yaml').write_text(
            'testing:\n  fast:\n    available: true\n    command: "python3 -c \'import app\'"\n')
        self.worktree = Path(self.tmp.name) / 'wt'
        self.git(self.main, 'worktree', 'add', '-q', '-b', 'feature', str(self.worktree))
        (self.worktree / '.opencode').mkdir()
        (self.worktree / '.opencode/project.yaml').write_text((self.main / '.opencode/project.yaml').read_text())
        self.engine = load('workflow_wt', 'scripts/skalling-workflow.py')

    def git(self, cwd, *args):
        return subprocess.run(['git', *args], cwd=cwd, env=ENV, capture_output=True, text=True, check=True)

    def call(self, actor, action, **payload):
        if action == 'start':
            payload.setdefault('intent', 'Preserve the declared fixture value')
        if action in {'approve', 'complete'}:
            payload.setdefault('coverage', [{'outcome_id': 'acceptance', 'check_index': 0,
                                            'observation': 'Fixture value assertion passed'}])
        return self.engine.operate({'project': str(self.worktree), 'actor': actor, 'session': actor + '-s',
                                    'action': action, 'payload': {'id': 'wt-1', **payload}})

    def test_full_workflow_from_a_worktree(self):
        started = self.call('alex', 'start', risk='low', scope='local', decision='none', files=['app.py'],
                            acceptance='value es 2', reuse='app.py')
        self.assertEqual(started['state'], 'implementation_ready')
        self.assertFalse((self.worktree / '.opencode/context/team.db').exists(), 'no se crea una base vacía en el worktree')
        (self.worktree / 'app.py').write_text('value = 2\n')
        self.assertEqual(self.call('teo', 'deliver')['state'], 'verified')
        self.assertEqual(self.call('alex', 'complete')['state'], 'completed')
        with closing(sqlite3.connect(self.db)) as conn, conn:
            self.assertEqual(conn.execute("SELECT agent FROM receipts WHERE task_id='wt-1'").fetchone()[0], 'auto')
        # El gate del worktree encuentra el receipt en la base del repositorio principal.
        cwd = os.getcwd()
        os.chdir(self.worktree)
        self.addCleanup(os.chdir, cwd)
        gate = load('gate_wt', 'scripts/hooks/git-gate.py')
        db = sqlite3.connect(self.db.as_uri() + '?mode=ro', uri=True)
        self.addCleanup(db.close)
        gate.check(['--cached'], db, 'pre-commit')

    def test_helpers_find_the_main_repository_memory(self):
        memory = subprocess.run(['bash', str(ROOT / 'scripts/teamdb-memory.sh'), '--project', str(self.worktree),
                                 'decision', 'wt', 'Desde worktree', 'guardada desde el worktree'],
                                env=ENV, capture_output=True, text=True)
        self.assertEqual(memory.returncode, 0, memory.stdout + memory.stderr)
        read = subprocess.run(['bash', str(ROOT / 'scripts/teamdb-read.sh'), str(self.worktree),
                               "SELECT slug FROM decisions WHERE slug='wt'"], env=ENV, capture_output=True, text=True)
        self.assertEqual(read.returncode, 0, read.stderr)
        self.assertIn('"slug": "wt"', read.stdout)
        with closing(sqlite3.connect(self.db)) as conn, conn:
            self.assertIsNotNone(conn.execute("SELECT 1 FROM decisions WHERE slug='wt'").fetchone())


if __name__ == '__main__':
    unittest.main()
