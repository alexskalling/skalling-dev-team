"""Regression scenarios from real empty capsules, stale prompts and blocked reads."""
import importlib.util
import json
import os
from pathlib import Path
import sqlite3
import subprocess
import sys
import tempfile
import unittest
from unittest.mock import patch

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT / 'scripts'))
from skalling_context import source_fingerprint, task_context, request_context

def load(name, filename):
    spec = importlib.util.spec_from_file_location(name, ROOT / 'scripts' / filename)
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module

memory = load('memory_write', 'skalling-memory-write.py')
config = load('project_config', 'skalling-project-config.py')

class MemoryEfficiency(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory()
        self.addCleanup(self.tmp.cleanup)
        self.project = Path(self.tmp.name)
        (self.project / '.opencode/context').mkdir(parents=True)
        self.path = self.project / '.opencode/context/team.db'
        self.db = sqlite3.connect(self.path)
        self.addCleanup(self.db.close)
        self.db.executescript((ROOT / 'sql/project-schema.sql').read_text())
        self.db.execute("INSERT INTO plans(slug,title,status) VALUES('plan','Campañas','approved')")
        self.db.execute("INSERT INTO tasks(plan_id,slug,title,purpose,acceptance_md) VALUES(1,'task','Campañas envío','No enviar duplicados','Un destinatario recibe un mensaje')")
        self.db.execute("INSERT INTO decisions(slug,title,body_md,status) VALUES('unique','Restricción de envío','Campañas deben deduplicar destinatarios','accepted')")
        self.db.commit()

    def test_no_link_still_delivers_relevant_full_memory_and_goal(self):
        data = task_context(self.db, self.project, 'plan', 'task')
        self.assertEqual(data['task']['purpose'], 'No enviar duplicados')
        self.assertEqual(data['decisions'][0]['body_md'], 'Campañas deben deduplicar destinatarios')
        self.assertEqual(data['decisions'][0]['provenance'], 'discovered')
        self.assertEqual(task_context(self.db, self.project, 'plan', 'task', discover=False)['decisions'], [])

    def test_exact_revision_reuses_between_request_and_task_but_never_other_callers(self):
        item = request_context(self.db, self.project, 'Campañas')['decisions'][0]
        key = item['read_key']
        repeated = task_context(self.db, self.project, 'plan', 'task', seen=[key])['decisions'][0]
        self.assertNotIn('body_md', repeated)
        self.assertTrue(repeated['already_read'])
        other = task_context(self.db, self.project, 'plan', 'task')['decisions'][0]
        self.assertIn('body_md', other)
        self.db.execute("UPDATE decisions SET body_md='Campañas: otra restricción' WHERE slug='unique'")
        changed = task_context(self.db, self.project, 'plan', 'task', seen=[key])['decisions'][0]
        self.assertIn('body_md', changed)
        self.assertNotEqual(changed['read_key'], key)

    def test_nested_source_changes_invalidate_but_memory_dumps_do_not(self):
        file = self.project / 'modules/campaign/send.ts'
        file.parent.mkdir(parents=True)
        file.write_text('export const limit = 1')
        first = source_fingerprint(self.project)
        file.write_text('export const limit = 2')
        self.assertNotEqual(first, source_fingerprint(self.project))
        dump = self.project / 'db/teamdb/team.dump.sql'
        dump.parent.mkdir(parents=True)
        baseline = source_fingerprint(self.project)
        dump.write_text('memory changed')
        self.assertEqual(baseline, source_fingerprint(self.project))

    def test_search_proceeds_with_live_writer_lock_and_literal_fts_punctuation(self):
        lock = self.project / '.opencode/context/.locks/team'
        lock.mkdir(parents=True)
        (lock / 'pid').write_text(str(os.getpid()))
        run = subprocess.run(['bash', str(ROOT / 'scripts/teamdb-search.sh'), 'Campañas', str(self.project)],
                             capture_output=True, text=True, timeout=3)
        self.assertEqual(run.returncode, 0, run.stderr)
        self.assertIn('unique', run.stdout)
        run = subprocess.run(['bash', str(ROOT / 'scripts/teamdb-search.sh'), '"OR" * : ( )', str(self.project)],
                             capture_output=True, text=True, timeout=3)
        self.assertEqual(run.returncode, 0, run.stderr)
        self.assertTrue(lock.exists())

    def test_batch_is_atomic_and_identical_memory_does_not_create_history(self):
        ops = [['concept', 'architecture', 'Arquitectura', 'Reglas'], ['preference', 'language', 'Español']]
        self.assertEqual(memory.write(self.path, ops), 2)
        revisions = self.db.execute('SELECT count(*) FROM data_revisions').fetchone()[0]
        self.assertEqual(memory.write(self.path, ops), 0)
        self.assertEqual(self.db.execute('SELECT count(*) FROM data_revisions').fetchone()[0], revisions)
        with self.assertRaises(sqlite3.IntegrityError):
            memory.write(self.path, [['preference', 'rollback', 'No conservar'], ['decision', 'bad', 'Bad', 'Body', 'invalid']])
        self.assertIsNone(self.db.execute("SELECT 1 FROM preferences WHERE slug='rollback'").fetchone())
        self.assertEqual(memory.write(self.path, [['concept', 'architecture', 'Arquitectura', 'Reglas nuevas']]), 1)
        self.assertGreater(self.db.execute('SELECT count(*) FROM data_revisions').fetchone()[0], revisions)

    def test_sync_preserves_header_model_backup_and_custom_body_until_explicit(self):
        agents = self.project / '.opencode/agents'
        agents.mkdir()
        path = agents / 'Teo.md'
        old = '---\nmodel: custom/model\npermission:\n  bash: ask\n---\nLegacy body\n'
        path.write_text(old)
        self.assertIn('Teo', config.sync_agents(self.project, check=True))
        self.assertIn('Teo', config.sync_agents(self.project))
        self.assertEqual(path.read_text(), old)
        config.sync_agents(self.project, force=True)
        self.assertIn('model: custom/model', path.read_text())
        self.assertIn('context_seen', path.read_text())
        backups = list(self.project.glob('.opencode/.skalling-backups/agents/*/Teo.md'))
        self.assertEqual(backups[0].read_text(), old)
        self.assertEqual(config.sync_agents(self.project, check=True), [])
        path.write_text(path.read_text() + '\nCustom instructions\n')
        config.sync_agents(self.project)
        self.assertIn('Custom instructions', path.read_text())

    def test_sync_uses_utf8_under_a_windows_legacy_locale(self):
        agents = self.project / '.opencode/agents'
        agents.mkdir()
        path = agents / 'Teo.md'
        old = '---\nmodel: custom/model\n---\nMemoria: 🚀\n'
        path.write_text(old, encoding='utf-8')
        read, write = Path.read_text, Path.write_text
        def windows_read(target, encoding=None, **kwargs):
            return read(target, encoding=encoding or 'cp1252', **kwargs)
        def windows_write(target, data, encoding=None, **kwargs):
            return write(target, data, encoding=encoding or 'cp1252', **kwargs)
        with patch.object(Path, 'read_text', windows_read), patch.object(Path, 'write_text', windows_write):
            config.sync_agents(self.project, force=True)
        self.assertIn('model: custom/model', path.read_text(encoding='utf-8'))
        backup = next(self.project.glob('.opencode/.skalling-backups/agents/*/Teo.md'))
        self.assertEqual(backup.read_text(encoding='utf-8'), old)

if __name__ == '__main__':
    unittest.main()
