"""El gate pre-push acepta los flujos normales de un equipo sin aflojar la regla.

Auditoría 2026-09-27: un merge sin conflictos o un rebase de trabajo ya
verificado bloqueaban el push, porque el digest exacto del diff cambia aunque
el cambio sea el mismo. Eso empuja a usar --no-verify a diario. Aquí se fija
qué se acepta (merge automático, rebase/cherry-pick del mismo cambio) y qué
sigue bloqueado (resolución manual, contenido nuevo, commits sin receipt).
"""
import hashlib
import sqlite3
import subprocess
import tempfile
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
ZERO = '0' * 40


class GitGateTeamFlows(unittest.TestCase):
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
        with sqlite3.connect(self.db) as conn:
            conn.executescript((ROOT / 'sql/project-schema.sql').read_text())
        (self.project / '.gitignore').write_text('.opencode/\n')
        self.write('app.py', ''.join(f'line_{n} = {n}\n' for n in range(1, 41)))
        self.commit_verified('base', '.gitignore', 'app.py')

    def git(self, *args, check=True):
        return subprocess.run(['git', *args], cwd=self.project, capture_output=True, text=True, check=check)

    def write(self, name, text):
        (self.project / name).write_text(text)

    def replace(self, old, new):
        path = self.project / 'app.py'
        path.write_text(path.read_text().replace(old, new))

    def seal(self):
        patch = self.git('diff', '--cached', '--', '.', ':(exclude)db/teamdb/team.dump.sql').stdout.rstrip('\n')
        digest = hashlib.sha256(patch.encode()).hexdigest()[:16]
        with sqlite3.connect(self.db) as conn:
            conn.execute("INSERT INTO receipts(id,task_id,agent,command,exit_code,ts,tree_hash) "
                         "VALUES(?,?,?,?,?,'2020-01-01 00:00:00',?)",
                         (digest + '-jhon', 'fixture', 'jhon', 'synthetic fixture verification', 0, digest))

    def commit_verified(self, message, *paths):
        self.git('add', *paths)
        self.seal()
        self.git('commit', '-qm', message, '--no-verify')

    def commit_unverified(self, message, *paths):
        self.git('add', *paths)
        self.git('commit', '-qm', message, '--no-verify')

    def push_check(self, ref='main', remote=ZERO):
        local = self.git('rev-parse', ref).stdout.strip()
        return subprocess.run(['bash', str(ROOT / 'scripts/hooks/pre-push')], cwd=self.project,
                              capture_output=True, text=True,
                              input=f'refs/heads/{ref} {local} refs/heads/{ref} {remote}\n')

    def diverge(self):
        self.git('checkout', '-qb', 'feat')
        self.replace('line_35 = 35', 'line_35 = "feat"')
        self.commit_verified('feat', 'app.py')
        self.git('checkout', '-q', 'main')
        self.replace('line_5 = 5', 'line_5 = "main"')
        self.commit_verified('main change', 'app.py')

    def test_clean_merge_of_verified_work_can_be_pushed(self):
        self.diverge()
        self.git('merge', '-q', '--no-edit', '--no-verify', 'feat')
        result = self.push_check()
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertIn('merge automático', result.stdout)

    def test_merge_with_manual_edits_still_needs_its_own_receipt(self):
        self.diverge()
        self.git('merge', '-q', '--no-commit', '--no-verify', 'feat')
        self.replace('line_20 = 20', 'line_20 = "colado en el merge"')
        self.git('add', 'app.py')
        self.git('commit', '-qm', 'merge editado', '--no-verify')
        result = self.push_check()
        self.assertNotEqual(result.returncode, 0)
        self.assertIn('falta revisión aprobada', result.stderr)

    def test_clean_merge_does_not_launder_unverified_side_commits(self):
        self.git('checkout', '-qb', 'feat')
        self.replace('line_35 = 35', 'line_35 = "sin revisar"')
        self.commit_unverified('feat sin receipt', 'app.py')
        self.git('checkout', '-q', 'main')
        self.replace('line_5 = 5', 'line_5 = "main"')
        self.commit_verified('main change', 'app.py')
        self.git('merge', '-q', '--no-edit', '--no-verify', 'feat')
        result = self.push_check()
        self.assertNotEqual(result.returncode, 0)
        self.assertIn('falta revisión aprobada', result.stderr)

    def test_rebased_verified_commit_can_be_pushed(self):
        self.diverge()
        self.git('checkout', '-q', 'feat')
        self.git('rebase', '-q', 'main')
        result = self.push_check('feat', self.git('rev-parse', 'main').stdout.strip())
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertIn('rebase/cherry-pick', result.stdout)

    def test_rebase_that_changes_the_content_needs_new_verification(self):
        self.diverge()
        self.git('checkout', '-q', 'feat')
        self.git('rebase', '-q', 'main')
        self.replace('line_35 = "feat"', 'line_35 = "feat" + "  cambiado"')
        self.git('add', 'app.py')
        self.git('commit', '-q', '--amend', '--no-edit', '--no-verify')
        result = self.push_check('feat', self.git('rev-parse', 'main').stdout.strip())
        self.assertNotEqual(result.returncode, 0)

    def test_unverified_commit_is_still_blocked(self):
        self.replace('line_10 = 10', 'line_10 = "a mano"')
        self.commit_unverified('commit a mano', 'app.py')
        result = self.push_check()
        self.assertNotEqual(result.returncode, 0)
        self.assertIn('falta revisión aprobada', result.stderr)


if __name__ == '__main__':
    unittest.main()
