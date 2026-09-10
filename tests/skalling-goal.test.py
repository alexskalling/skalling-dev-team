import hashlib
import importlib.util
import sqlite3
import subprocess
import tempfile
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
spec = importlib.util.spec_from_file_location('goal', ROOT / 'scripts/skalling-goal.py')
goal = importlib.util.module_from_spec(spec)
spec.loader.exec_module(goal)


class GoalTests(unittest.TestCase):
    def setUp(self):
        tmp = tempfile.TemporaryDirectory()
        self.addCleanup(tmp.cleanup)
        self.root = Path(tmp.name).resolve()
        self.git('init', '-q')
        self.git('config', 'user.email', 'fixture@example.test')
        self.git('config', 'user.name', 'Fixture')
        (self.root / '.gitignore').write_text('.opencode/\n')
        (self.root / 'app.py').write_text('value = 1\n')
        self.git('add', '.')
        self.git('commit', '-qm', 'base')

    def git(self, *args):
        return subprocess.check_output(['git', '-C', str(self.root), *args], stderr=subprocess.PIPE)

    def act(self, action, **payload):
        return goal.operate(self.root, 'session-1', action, payload)

    def start(self):
        return self.act('start', objective="Cambiar value; no publicar. ' ; DROP TABLE receipts; --")

    def test_status_does_not_create_database(self):
        self.assertIsNone(self.act('status'))
        self.assertFalse((self.root / '.opencode').exists())

    def test_persisted_session_and_controls(self):
        initial = self.start()
        self.assertEqual(self.act('status')['objective'], initial['objective'])
        self.assertIsNone(goal.operate(self.root, 'other', 'status', {}))
        with self.assertRaises(ValueError):
            goal.operate(self.root, 'other', 'start', {'objective': 'competing'})
        self.assertEqual(self.act('pause')['status'], 'paused')
        self.assertEqual(self.act('tick')['status'], 'paused')
        self.assertEqual(self.act('resume')['status'], 'active')
        self.assertEqual(self.act('cancel')['status'], 'cancelled')
        with self.assertRaises(ValueError):
            self.act('resume')

    def test_no_progress_stops_and_checkpoint_counts(self):
        self.start()
        self.assertEqual(self.act('tick')['stagnant'], 1)
        self.act('checkpoint', summary='Inspección terminada; propuesta concreta registrada')
        self.assertEqual(self.act('tick')['stagnant'], 0)
        for _ in range(3):
            result = self.act('tick')
        self.assertEqual(result['status'], 'blocked')

    def test_maximum_continuations_even_with_progress(self):
        self.start()
        for i in range(20):
            self.act('checkpoint', summary=f'Paso comprobado {i}')
            result = self.act('tick')
        self.assertEqual(result['status'], 'blocked')
        self.assertEqual(result['turns'], 20)

    def test_preexisting_staged_files_rejected(self):
        (self.root / 'app.py').write_text('value = 2\n')
        self.git('add', 'app.py')
        with self.assertRaisesRegex(ValueError, 'previamente preparados'):
            self.start()

    def test_dirty_files_and_external_paths_protected(self):
        (self.root / 'app.py').write_text('value = 2\n')
        self.start()
        self.act('checkpoint', summary='fixture')
        for file in ('app.py', '../outside', '.git/config', '.'):
            with self.assertRaises(ValueError):
                self.act('commit', message='Cambio', files=[file])

    def test_commit_needs_checkpoint_and_exact_evidence_then_finishes_once(self):
        self.start()
        (self.root / 'app.py').write_text('value = 2\n')
        with self.assertRaisesRegex(ValueError, 'checkpoint'):
            self.act('commit', message='Cambio', files=['app.py'])
        self.act('checkpoint', summary='Evidencia sintética SOLO para prueba del protocolo')
        with self.assertRaisesRegex(ValueError, 'skalling-review'):
            self.act('commit', message='Cambio', files=['app.py'])
        patch = self.git('diff', '--cached', '--', '.', ':(exclude)db/teamdb/team.dump.sql').rstrip(b'\n')
        digest = hashlib.sha256(patch).hexdigest()[:16]
        with sqlite3.connect(self.root / '.opencode/context/team.db') as db:
            db.execute("INSERT INTO receipts(id,task_id,agent,command,exit_code,tree_hash,ts) VALUES(?,?,?,?,?,?,CURRENT_TIMESTAMP)",
                       ('fixture', 'fixture', 'fixture', 'synthetic test evidence', 0, digest))
        result = self.act('commit', message='test: cambia valor de fixture', files=['app.py'])
        self.assertEqual(result['status'], 'completed')
        self.assertEqual(result['commit_sha'], self.git('rev-parse', 'HEAD').decode().strip())
        self.assertEqual(self.git('rev-list', '--count', 'HEAD').strip(), b'2')
        for action in ('commit', 'pause', 'block'):
            with self.assertRaises(ValueError):
                self.act(action, message='Otro', files=['app.py'])

    def test_changed_head_blocks_commit(self):
        self.start()
        self.act('checkpoint', summary='fixture')
        self.git('commit', '--allow-empty', '-qm', 'concurrent commit')
        with self.assertRaisesRegex(ValueError, 'HEAD'):
            self.act('commit', message='Cambio', files=['app.py'])

    def test_foreign_index_and_missing_authority_rejected(self):
        self.start()
        self.act('checkpoint', summary='fixture')
        (self.root / 'other.txt').write_text('other work')
        self.git('add', 'other.txt')
        with self.assertRaisesRegex(ValueError, 'ajenos'):
            self.act('commit', message='Cambio', files=['app.py'])
        result = subprocess.run(['bash', str(ROOT / 'scripts/skalling-goal.sh'), 'start', 'fake'],
                                cwd=self.root, capture_output=True, text=True)
        self.assertNotEqual(result.returncode, 0)


if __name__ == '__main__':
    unittest.main()
