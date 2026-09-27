"""Camino humano para commitear (auditoría 2026-09-27).

Una persona que commitea desde su terminal no tenía una forma documentada de
pasar el gate: solo existía sellar "como jhon". skalling-approve.sh corre el
test real del proyecto sobre lo staged y deja un receipt atribuido a
"humano"; el gate lo acepta igual que la verificación de Jhon. Se fija que:
tests verdes habilitan el commit, rojos lo bloquean, dentro de OpenCode se
niega, y un receipt "humano" sin evidencia calculada no abre nada.
"""
import os
from contextlib import closing
import sqlite3
import subprocess
import tempfile
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
APPROVE = ROOT / 'scripts/skalling-approve.sh'
GATE = ROOT / 'scripts/hooks/git-gate.py'


class HumanApprove(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory()
        self.addCleanup(self.tmp.cleanup)
        self.project = Path(self.tmp.name)
        self.git('init', '-q', '-b', 'main')
        self.git('config', 'user.email', 'fixture@example.test')
        self.git('config', 'user.name', 'Fixture')
        context = self.project / '.opencode/context'
        context.mkdir(parents=True)
        self.db = context / 'team.db'
        with closing(sqlite3.connect(self.db)) as conn, conn:
            conn.executescript((ROOT / 'sql/project-schema.sql').read_text())
        (self.project / '.gitignore').write_text('.opencode/context/\n')
        self.set_test_command('true')
        (self.project / 'app.py').write_text('x = 1\n')
        self.git('add', '-A')
        self.git('commit', '-qm', 'base', '--no-verify')
        self.env = {k: v for k, v in os.environ.items() if not k.startswith(('SKALLING_', 'TEAMDB_'))}
        self.env['PYTHONDONTWRITEBYTECODE'] = '1'

    def git(self, *args):
        return subprocess.run(['git', *args], cwd=self.project, capture_output=True, text=True, check=True)

    def set_test_command(self, command):
        (self.project / '.opencode/project.yaml').write_text(
            f'testing:\n  unit:\n    available: true\n    command: "{command}"\n')

    def stage_change(self, text):
        (self.project / 'app.py').write_text(text)
        self.git('add', 'app.py')

    def approve(self, **extra):
        return subprocess.run(['bash', str(APPROVE), str(self.project)], cwd=self.project, capture_output=True,
                              text=True, env={**self.env, **extra})

    def gate(self):
        return subprocess.run(['python3', str(GATE), 'pre-commit'], cwd=self.project, capture_output=True, text=True)

    def test_green_tests_enable_commit_attributed_to_human(self):
        self.stage_change('x = 2\n')
        self.assertIn('falta revisión aprobada', self.gate().stderr)
        self.assertIn('skalling-approve.sh', self.gate().stderr)
        result = self.approve()
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(self.gate().returncode, 0, self.gate().stderr)
        with closing(sqlite3.connect(self.db)) as conn, conn:
            agent, exit_code = conn.execute('SELECT agent, exit_code FROM receipts ORDER BY ts DESC LIMIT 1').fetchone()
        self.assertEqual((agent, exit_code), ('humano', 0))

    def test_red_tests_keep_commit_blocked(self):
        self.set_test_command('false')
        self.stage_change('x = 3\n')
        self.assertNotEqual(self.approve().returncode, 0)
        self.assertNotEqual(self.gate().returncode, 0)

    def test_refuses_inside_opencode(self):
        self.stage_change('x = 4\n')
        result = self.approve(SKALLING_RUNTIME_AGENT='teo')
        self.assertEqual(result.returncode, 2)
        self.assertNotEqual(self.gate().returncode, 0)

    def test_human_receipt_without_computed_evidence_does_not_open_gate(self):
        self.stage_change('x = 5\n')
        patch = subprocess.run(['git', 'diff', '--cached', '--', '.', ':(exclude)db/teamdb/team.dump.sql'],
                               cwd=self.project, capture_output=True, check=True).stdout.rstrip(b'\n')
        import hashlib
        digest = hashlib.sha256(patch).hexdigest()[:16]
        with closing(sqlite3.connect(self.db)) as conn, conn:
            conn.execute("INSERT INTO receipts(id,task_id,agent,command,exit_code,ts,tree_hash) "
                         "VALUES('r','t','humano','a mano',0,'2020-01-01',?)", (digest,))
        self.assertNotEqual(self.gate().returncode, 0)


if __name__ == '__main__':
    unittest.main()
