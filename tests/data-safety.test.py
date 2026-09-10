import importlib.util
import sqlite3
import sys
import tempfile
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT / 'scripts'))
from teamdb_guard import connect
spec = importlib.util.spec_from_file_location('destructive', ROOT / 'scripts/teamdb-destructive.py')
destructive = importlib.util.module_from_spec(spec)
spec.loader.exec_module(destructive)


class DataSafety(unittest.TestCase):
    def open(self, path=None, guarded=False, **kwargs):
        connection = (connect if guarded else sqlite3.connect)(path or self.db, **kwargs)
        self.addCleanup(connection.close)
        return connection

    def setUp(self):
        temp = tempfile.TemporaryDirectory()
        self.addCleanup(temp.cleanup)
        self.db = Path(temp.name) / 'team.db'
        with self.open() as conn:
            conn.executescript((ROOT / 'sql/project-schema.sql').read_text())
            conn.execute("INSERT INTO concepts(slug,title,body_md,updated_at) VALUES('one','Title','Original',CURRENT_TIMESTAMP)")

    def test_additions_and_updates_preserve_old_content(self):
        with self.open(guarded=True) as db:
            db.execute("UPDATE concepts SET body_md='Revised' WHERE slug='one'")
            db.execute('ALTER TABLE concepts ADD COLUMN extra TEXT')
            db.execute('CREATE TABLE additional(id INTEGER)')
            self.assertIn('Original', db.execute('SELECT previous_json FROM data_revisions').fetchone()[0])
            self.assertEqual(db.execute("SELECT body_md FROM concepts WHERE slug='one'").fetchone()[0], 'Revised')

    def test_destructive_sql_is_rejected(self):
        for sql in ("DELETE FROM concepts", "WITH x AS (SELECT 1) DELETE FROM concepts",
                    'DROP TABLE concepts', 'ALTER TABLE concepts DROP COLUMN body_md',
                    "INSERT OR REPLACE INTO concepts(id,slug,title) VALUES(1,'one','Replace')",
                    "UPDATE concepts SET body_md=''", "UPDATE concepts SET title=NULL",
                    'PRAGMA writable_schema=ON'):
            with self.subTest(sql=sql), self.open(guarded=True) as db:
                with self.assertRaises(sqlite3.DatabaseError):
                    db.execute(sql)
                self.assertEqual(db.execute('SELECT count(*) FROM concepts').fetchone()[0], 1)

    def test_trigger_delete_and_cursor_bypass_are_blocked(self):
        with self.open() as db:
            db.execute('CREATE TRIGGER hostile AFTER INSERT ON preferences BEGIN DELETE FROM concepts; END')
        with self.open(guarded=True) as db:
            with self.assertRaises(sqlite3.DatabaseError):
                db.execute("INSERT INTO preferences(slug,body_md) VALUES('bad','bad')")
            with self.assertRaises(sqlite3.DatabaseError):
                db.cursor().execute('DELETE FROM concepts')

    def test_queries_cannot_write_and_quoted_words_are_data(self):
        with self.open(guarded=True, readonly=True) as db:
            with self.assertRaises(sqlite3.DatabaseError):
                db.execute('DELETE FROM concepts')
        with self.open(guarded=True) as db:
            db.execute("UPDATE concepts SET body_md=?", ('DELETE FROM is documentation',))

    def request(self, sql='DELETE FROM concepts WHERE slug=?'):
        return dict(project=str(self.db.parent), database='team.db', sql=sql, params=['one'])

    def test_approved_operation_creates_restorable_backup(self):
        request = self.request()
        preview = destructive.operate({**request, 'action': 'preview'})
        result = destructive.operate({**request, 'action': 'apply', 'state_hash': preview['state_hash']})
        with self.open(result['backup']) as before, self.open() as after:
            self.assertEqual(before.execute('SELECT count(*) FROM concepts').fetchone()[0], 1)
            self.assertEqual(after.execute('SELECT count(*) FROM concepts').fetchone()[0], 0)

    def test_stale_approval_multiple_statements_and_external_targets_rejected(self):
        request = self.request()
        preview = destructive.operate({**request, 'action': 'preview'})
        with self.open(guarded=True) as db:
            db.execute("UPDATE concepts SET title='New title'")
        with self.assertRaisesRegex(ValueError, 'cambió'):
            destructive.operate({**request, 'action': 'apply', 'state_hash': preview['state_hash']})
        with self.assertRaises(sqlite3.Error):
            destructive.operate({**request, 'sql': 'DELETE FROM concepts; DROP TABLE concepts', 'action': 'preview'})
        with self.assertRaises(ValueError):
            destructive.operate({**request, 'database': '../outside.db', 'action': 'preview'})


if __name__ == '__main__':
    unittest.main()
