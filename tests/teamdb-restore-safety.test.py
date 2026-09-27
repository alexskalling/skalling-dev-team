"""Restaurar la memoria no ejecuta nada y no pierde lo confirmado.

Auditoría externa v0.12.0:
  #3 teamdb-restore.sh entregaba el dump versionado (lo puede tocar cualquier
     PR) a sqlite3 como script: una línea `.shell ...` ejecutaba comandos, y
     teamdb-init lo corre solo en cada clon nuevo.
  #4 el respaldo previo copiaba solo team.db: lo confirmado que seguía en el
     WAL no quedaba respaldado, y si el respaldo fallaba se seguía igual
     (incluso con --full-reset, que borra la base).
"""
import os
import shutil
import sqlite3
import subprocess
import tempfile
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]


class RestoreSafety(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory()
        self.addCleanup(self.tmp.cleanup)
        self.root = Path(self.tmp.name) / 'project'
        (self.root / '.opencode/context').mkdir(parents=True)
        (self.root / 'db/teamdb').mkdir(parents=True)
        self.db = self.root / '.opencode/context/team.db'
        self.dump = self.root / 'db/teamdb/team.dump.sql'
        self.marker = Path(self.tmp.name) / 'EJECUTADO'

    def restore(self, *args):
        return subprocess.run(['bash', str(ROOT / 'scripts/teamdb-restore.sh'), str(self.root), *args],
                              capture_output=True, text=True, env={**os.environ, 'SKALLING_ROOT': str(ROOT)})

    def valid_row(self):
        return ('INSERT INTO "preferences" ("id","slug","scope","body_md") '
                "VALUES (1,'tono','global','Formal');\n")

    def test_dot_commands_in_the_dump_never_run(self):
        for payload in (f'.shell touch {self.marker}\n', f'.system touch {self.marker}\n',
                        "ATTACH DATABASE '/tmp/x.db' AS x;\n", 'DROP TABLE concepts;\n',
                        'INSERT INTO "sqlite_master" ("name") VALUES (\'x\');\n'):
            with self.subTest(payload=payload.strip()):
                self.dump.write_text(self.valid_row() + payload)
                if self.db.exists():
                    self.db.unlink()
                result = self.restore('--force')
                self.assertNotEqual(result.returncode, 0, result.stdout)
                self.assertIn('no son datos', result.stderr)
                self.assertFalse(self.marker.exists(), 'el dump ejecutó un comando')

    def test_hostile_dump_leaves_an_existing_base_untouched(self):
        subprocess.run(['bash', str(ROOT / 'scripts/teamdb-init.sh'), str(self.root)], capture_output=True,
                       check=True, env={**os.environ, 'SKALLING_ROOT': str(ROOT)})
        with sqlite3.connect(self.db) as conn:
            conn.execute("INSERT INTO preferences (slug,scope,body_md) VALUES ('propia','global','no tocar')")
        self.dump.write_text(self.valid_row() + 'DELETE FROM preferences;\n')
        self.assertNotEqual(self.restore('--force').returncode, 0)
        with sqlite3.connect(self.db) as conn:
            self.assertEqual(conn.execute("SELECT body_md FROM preferences WHERE slug='propia'").fetchone()[0], 'no tocar')
            self.assertIsNone(conn.execute("SELECT 1 FROM preferences WHERE slug='tono'").fetchone())

    def test_valid_dump_restores_and_is_idempotent(self):
        self.dump.write_text(self.valid_row())
        first = self.restore()
        self.assertEqual(first.returncode, 0, first.stderr)
        second = self.restore('--force')
        self.assertEqual(second.returncode, 0, second.stderr)
        with sqlite3.connect(self.db) as conn:
            self.assertEqual(conn.execute("SELECT count(*), max(body_md) FROM preferences").fetchone(), (1, 'Formal'))
            self.assertEqual(conn.execute("PRAGMA integrity_check").fetchone()[0], 'ok')

    def test_backup_keeps_what_is_still_in_the_wal(self):
        subprocess.run(['bash', str(ROOT / 'scripts/teamdb-init.sh'), str(self.root)], capture_output=True,
                       check=True, env={**os.environ, 'SKALLING_ROOT': str(ROOT)})
        holder = sqlite3.connect(self.db)
        holder.execute('PRAGMA journal_mode=WAL')
        holder.execute('PRAGMA wal_autocheckpoint=0')
        holder.execute("INSERT INTO preferences (slug,scope,body_md) VALUES ('reciente','global','en el WAL')")
        holder.commit()
        self.assertGreater(Path(str(self.db) + '-wal').stat().st_size, 0)
        self.dump.write_text(self.valid_row())
        result = self.restore('--force')
        holder.close()
        self.assertEqual(result.returncode, 0, result.stderr)
        backups = sorted((self.db.parent / '.backups').glob('team.db.backup-*'))
        self.assertTrue(backups)
        with sqlite3.connect(backups[-1]) as conn:
            self.assertEqual(conn.execute("SELECT body_md FROM preferences WHERE slug='reciente'").fetchone()[0], 'en el WAL')

    def test_failed_backup_aborts_before_a_full_reset(self):
        subprocess.run(['bash', str(ROOT / 'scripts/teamdb-init.sh'), str(self.root)], capture_output=True,
                       check=True, env={**os.environ, 'SKALLING_ROOT': str(ROOT)})
        with sqlite3.connect(self.db) as conn:
            conn.execute("INSERT INTO preferences (slug,scope,body_md) VALUES ('valiosa','global','trabajo')")
        backups = self.db.parent / '.backups'
        shutil.rmtree(backups, ignore_errors=True)
        backups.write_text('no es un directorio')   # el respaldo no puede escribirse
        self.dump.write_text(self.valid_row())
        result = self.restore('--full-reset')
        self.assertNotEqual(result.returncode, 0)
        self.assertIn('restauración abortada sin cambios', result.stderr)
        with sqlite3.connect(self.db) as conn:
            self.assertEqual(conn.execute("SELECT body_md FROM preferences WHERE slug='valiosa'").fetchone()[0], 'trabajo')


    # ── Auditoría de c7517ea: la recuperación es atómica ──

    def init(self):
        subprocess.run(['bash', str(ROOT / 'scripts/teamdb-init.sh'), str(self.root)], capture_output=True,
                       check=True, env={**os.environ, 'SKALLING_ROOT': str(ROOT)})

    def test_bad_column_with_full_reset_leaves_the_active_base_intact(self):
        self.init()
        with sqlite3.connect(self.db) as conn:
            conn.execute("INSERT INTO preferences (slug,scope,body_md) VALUES ('valiosa','global','trabajo')")
        self.dump.write_text('INSERT INTO "preferences" ("id","slug","scope","no_existe") VALUES (9,\'x\',\'global\',1);\n')
        result = self.restore('--full-reset')
        self.assertNotEqual(result.returncode, 0)
        self.assertIn('queda sin cambios', result.stderr)
        with sqlite3.connect(self.db) as conn:
            self.assertEqual(conn.execute("SELECT body_md FROM preferences WHERE slug='valiosa'").fetchone()[0], 'trabajo')
        self.assertFalse(list(self.db.parent.glob('team.db.restore-*')))

    def corrupt(self):
        self.init()
        with sqlite3.connect(self.db) as conn:
            conn.execute('PRAGMA journal_mode=DELETE')
        data = bytearray(self.db.read_bytes())
        data[100:4096] = b'\xff' * (4096 - 100)        # cabecera y primera página destruidas
        self.db.write_bytes(bytes(data))
        return bytes(data)

    def test_corrupt_base_can_be_rebuilt_with_full_reset_keeping_a_raw_copy(self):
        original = self.corrupt()
        self.dump.write_text(self.valid_row())
        result = self.restore('--full-reset')
        self.assertEqual(result.returncode, 0, result.stderr)
        raw = list((self.db.parent / '.backups').glob('team.db.corrupt-*'))
        self.assertTrue(raw)
        self.assertEqual(raw[0].read_bytes(), original)
        with sqlite3.connect(self.db) as conn:
            self.assertEqual(conn.execute("SELECT body_md FROM preferences WHERE slug='tono'").fetchone()[0], 'Formal')
            self.assertEqual(conn.execute('PRAGMA integrity_check').fetchone()[0], 'ok')

    def test_corrupt_base_is_not_touched_by_force_without_full_reset(self):
        original = self.corrupt()
        self.dump.write_text(self.valid_row())
        result = self.restore('--force')
        self.assertNotEqual(result.returncode, 0)
        self.assertIn('--full-reset', result.stderr)
        self.assertEqual(self.db.read_bytes(), original)


if __name__ == '__main__':
    unittest.main()
