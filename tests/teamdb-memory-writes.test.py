"""Pau escribe memoria por el helper protegido y queda versionada.

Prueba real con OpenCode 2.0.18 (27-09-2026): los triggers de
memory_versions usaban DELETE y teamdb_guard prohíbe DELETE aun dentro de un
trigger, así que TODA escritura de memoria por teamdb-memory.sh fallaba con
"not authorized". Los tests del merge escribían con sqlite3 directo y no lo
veían: este usa el mismo camino que el agente.
"""
import json
import os
from contextlib import closing
import sqlite3
import subprocess
import tempfile
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]


class MemoryWrites(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory()
        self.addCleanup(self.tmp.cleanup)
        self.project = Path(self.tmp.name)
        (self.project / '.opencode/context').mkdir(parents=True)
        subprocess.run(['bash', str(ROOT / 'scripts/teamdb-init.sh'), str(self.project)], check=True,
                       capture_output=True, env={**os.environ, 'SKALLING_ROOT': str(ROOT)})
        self.db = self.project / '.opencode/context/team.db'

    def memory(self, *args):
        result = subprocess.run(['bash', str(ROOT / 'scripts/teamdb-memory.sh'), '--project', str(self.project), *args],
                                capture_output=True, text=True, env={**os.environ, 'SKALLING_RUNTIME_AGENT': 'pau'})
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
        self.assertNotIn('not authorized', result.stdout)
        return json.loads(result.stdout.strip().splitlines()[0])

    def versions(self):
        with closing(sqlite3.connect(self.db)) as conn, conn:
            return dict(((t, s), v) for t, s, v in conn.execute('SELECT table_name, slug, updated_at FROM memory_versions'))

    def test_every_kind_of_memory_is_written_through_the_guarded_helper(self):
        self.memory('concept', 'auth', 'Autenticación', 'JWT con refresh rotativo')
        self.memory('decision', 'orm', 'ORM', 'Usamos Drizzle', 'accepted')
        self.memory('preference', 'tono', 'Formal')
        self.memory('problem', 'flaky', 'CI intermitente', 'Falla 1 de 10', 'Reintentar el job')
        self.assertEqual(set(self.versions()), {('decisions', 'orm'), ('preferences', 'tono'), ('known_problems', 'flaky')})

    def test_updates_and_status_changes_bump_the_version(self):
        self.memory('decision', 'orm', 'ORM', 'Usamos Prisma', 'accepted')
        before = self.versions()[('decisions', 'orm')]
        self.memory('decision', 'orm', 'ORM', 'Reemplazado por Drizzle', 'superseded')
        after = self.versions()[('decisions', 'orm')]
        self.assertGreater(after, before)
        with closing(sqlite3.connect(self.db)) as conn, conn:
            self.assertEqual(conn.execute("SELECT status FROM decisions WHERE slug='orm'").fetchone()[0], 'superseded')
            self.assertEqual(conn.execute("PRAGMA integrity_check").fetchone()[0], 'ok')


if __name__ == '__main__':
    unittest.main()
