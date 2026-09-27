import hashlib
import os
import sqlite3
import subprocess
import tempfile
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]


class GitClose(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory()
        self.addCleanup(self.tmp.cleanup)
        self.project = Path(self.tmp.name)
        self.git('init', '-q')
        self.git('config', 'user.email', 'fixture@example.test')
        self.git('config', 'user.name', 'Fixture')
        (self.project / 'app.py').write_text('value = 1\n')
        self.git('add', 'app.py')
        self.git('commit', '-qm', 'base')
        self.base = self.git('rev-parse', 'HEAD').stdout.strip()
        context = self.project / '.opencode/context'
        context.mkdir(parents=True)
        self.db = context / 'team.db'
        with sqlite3.connect(self.db) as conn:
            conn.executescript((ROOT / 'sql/project-schema.sql').read_text())
        (self.project / '.gitignore').write_text('.opencode/\n')

    def git(self, *args):
        return subprocess.run(['git', *args], cwd=self.project, capture_output=True, text=True, check=True)

    def change(self, number):
        (self.project / 'app.py').write_text(f'value = {number}\n')
        self.git('add', 'app.py')

    def receipt(self, success=0, agent='jhon', command=None):
        # Comando con la forma que deja cada productor real de evidencia; el
        # gate rechaza receipts hechos a mano (auditoría externa v0.12.0 #2).
        command = command or {'luz': 'review --lens risk'}.get(agent, 'skalling-verify.sh (test real del proyecto)')
        patch = self.git('diff', '--cached', '--', '.', ':(exclude)db/teamdb/team.dump.sql').stdout.rstrip('\n')
        digest = hashlib.sha256(patch.encode()).hexdigest()[:16]
        with sqlite3.connect(self.db) as conn:
            conn.execute("INSERT INTO receipts(id,task_id,agent,command,exit_code,ts,tree_hash) VALUES(?,?,?,?,?,'2020-01-01 00:00:00',?)",
                         (digest + str(success) + agent + command, 'fixture', agent, command, success, digest))

    def hook(self, name, input=None):
        return subprocess.run(['bash', str(ROOT / 'scripts/hooks' / name)], cwd=self.project,
                              capture_output=True, text=True, input=input)

    def test_old_evidence_and_unstaged_work_do_not_block(self):
        self.change(2)
        self.receipt()
        (self.project / 'app.py').write_text('value = 999\n')
        before = self.git('diff', '--cached').stdout
        result = self.hook('pre-commit')
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(before, self.git('diff', '--cached').stdout)
        self.assertFalse((self.project / 'db/teamdb/team.dump.sql').exists())

    def test_only_verifier_receipts_unlock_commit(self):
        # Un comprobante de quien orquesta o implementó no prueba nada: el
        # commit exige a Jhon o Luz sobre el candidato exacto.
        self.change(2)
        for agent in ('alex', 'teo'):
            self.receipt(agent=agent)
            result = self.hook('pre-commit')
            self.assertNotEqual(result.returncode, 0)
            self.assertIn('Jhon', result.stderr)
        # Un 'review-seal' de Luz sin revisión (valores por defecto) tampoco.
        self.receipt(agent='luz', command='review-seal')
        self.assertNotEqual(self.hook('pre-commit').returncode, 0)
        self.receipt(agent='luz')
        self.assertEqual(self.hook('pre-commit').returncode, 0)

    def test_changed_or_failed_evidence_blocks(self):
        self.change(2)
        self.receipt(success=1)
        self.assertNotEqual(self.hook('pre-commit').returncode, 0)
        self.receipt()
        self.change(3)
        self.assertNotEqual(self.hook('pre-commit').returncode, 0)

    def test_multiple_commits_and_memory_changes_do_not_block_push(self):
        for value in (2, 3):
            self.change(value)
            self.receipt()
            self.git('commit', '-qm', f'change {value}')
        with sqlite3.connect(self.db) as conn:
            conn.execute("INSERT INTO preferences(slug,body_md,scope) VALUES('new-memory','Una decisión posterior','project')")
        head = self.git('rev-parse', 'HEAD').stdout.strip()
        result = self.hook('pre-push', f'refs/heads/main {head} refs/heads/main {self.base}\n')
        self.assertEqual(result.returncode, 0, result.stderr)

    def test_unreviewed_commit_is_rejected_without_dump(self):
        self.change(2)
        self.git('commit', '-qm', 'unreviewed')
        head = self.git('rev-parse', 'HEAD').stdout.strip()
        self.assertNotEqual(self.hook('pre-push', f'refs/heads/main {head} refs/heads/main {self.base}\n').returncode, 0)

    def test_secret_in_staged_dump_blocks_without_cleaning_database(self):
        folder = self.project / 'db/teamdb'
        folder.mkdir(parents=True)
        (folder / 'team.dump.sql').write_text('token=' + 'ghp_' + 'A' * 30)
        self.git('add', 'db/teamdb/team.dump.sql')
        before = self.db.read_bytes()
        self.assertNotEqual(self.hook('pre-commit').returncode, 0)
        self.assertEqual(before, self.db.read_bytes())

    def test_current_provider_secret_formats_block_commit(self):
        # Auditoría 2026-09-27: el regex original no detectaba ninguno de
        # estos formatos. Se arman por concatenación para no disparar el gate
        # sobre este mismo archivo.
        samples = ['sk-' + 'ant-api03-' + 'A1b2C3d4' * 4, 'sk-' + 'proj-' + 'A1b2C3d4' * 4,
                   'github_' + 'pat_' + '11AB' * 8, 'glpat' + '-' + 'A1b2C3d4' * 3,
                   'xox' + 'b-1234567890-' + 'abcdefghijkl', 'sk_' + 'live_' + 'A1b2C3d4' * 3,
                   'aws_secret_' + 'access_key = ' + 'A1b2C3d4/+' * 4,
                   'postgres://' + 'admin:' + 'Pr0dS3cret' + '@db.internal/app']
        for sample in samples:
            with self.subTest(sample=sample[:12]):
                (self.project / 'config.py').write_text(f'VALUE = "{sample}"\n')
                self.git('add', 'config.py')
                result = self.hook('pre-commit')
                self.assertNotEqual(result.returncode, 0)
                self.assertIn('posible secreto', result.stderr)
        (self.project / 'config.py').write_text('URL = "postgres://user:${DB_PASSWORD}@localhost/app"\n'
                                                'NAME = "task-context-capsule-builder-name"\n')
        self.git('add', 'config.py')
        self.assertNotIn('posible secreto', self.hook('pre-commit').stderr)

    def test_new_branch_checks_changes_not_already_on_remote(self):
        self.git('update-ref', 'refs/remotes/origin/main', self.base)
        self.change(2)
        self.receipt()
        self.git('commit', '-qm', 'reviewed')
        head = self.git('rev-parse', 'HEAD').stdout.strip()
        result = self.hook('pre-push', f'refs/heads/feature {head} refs/heads/feature ' + '0' * 40 + '\n')
        self.assertEqual(result.returncode, 0, result.stderr)

    def test_seal_uses_staged_changes_and_does_not_export_memory(self):
        self.change(2)
        patch = self.git('diff', '--cached', '--', '.', ':(exclude)db/teamdb/team.dump.sql').stdout.rstrip('\n')
        expected = hashlib.sha256(patch.encode()).hexdigest()[:16]
        (self.project / 'app.py').write_text('value = 999\n')
        # Luz con la evidencia que deja skalling-review.sh (el único sello de
        # luz aceptado); un agente inventado ('fixture') ya no sella.
        env = {**os.environ, 'TEAMDB_CLAIM_COMMAND': 'review --lens all', 'TEAMDB_CLAIM_EXIT_CODE': '0',
               'TEAMDB_CLAIM_OUTPUT_SUMMARY': '{"total":0}'}
        env.pop('SKALLING_RUNTIME_AGENT', None)
        bogus = subprocess.run(['bash', str(ROOT / 'scripts/teamdb-seal-receipt.sh'),
                                'fixture', 'fixture', str(self.project)], capture_output=True, text=True, env=env)
        self.assertEqual(bogus.returncode, 2)
        result = subprocess.run(['bash', str(ROOT / 'scripts/teamdb-seal-receipt.sh'),
                                 'fixture', 'luz', str(self.project)], capture_output=True, text=True, env=env)
        self.assertEqual(result.returncode, 0, result.stderr)
        with sqlite3.connect(self.db) as conn:
            self.assertEqual(conn.execute('SELECT tree_hash FROM receipts').fetchone()[0], expected)
        self.assertFalse((self.project / 'db/teamdb/team.dump.sql').exists())

    def test_delete_ref_does_not_require_new_review(self):
        zeros = '0' * 40
        self.assertEqual(self.hook('pre-push', f'refs/heads/old {zeros} refs/heads/old {self.base}\n').returncode, 0)


if __name__ == '__main__':
    unittest.main()
