"""La memoria con saltos de línea viaja entre máquinas (dump → merge).

Auditoría 2026-09-27: teamdb-merge.sh leía el dump línea por línea y
descartaba en silencio todo INSERT con un valor multilínea. En el dump real
del repo, 0/1 conceptos, 0/2 propuestas y 0/2 planes eran sincronizables:
el conocimiento del equipo nunca llegaba a los demás.
"""
import shutil
import sqlite3
import subprocess
import tempfile
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
BODY = "# Auth\n\n## What\nJWT con 'refresh' rotativo.\r\n\n## Why\n- línea con, comas\n- y \"comillas\"\n"


class TeamdbMergeMultiline(unittest.TestCase):
    def project(self, name):
        root = Path(self.tmp.name) / name
        (root / '.opencode/context').mkdir(parents=True)
        (root / 'db/teamdb').mkdir(parents=True)
        (root / 'scripts/lib').mkdir(parents=True)
        (root / 'sql').mkdir()
        shutil.copy(ROOT / 'sql/project-schema.sql', root / 'sql')
        for script in ('teamdb-dump.sh', 'teamdb-restore.sh', 'teamdb-merge.sh', 'teamdb_dump.py'):
            shutil.copy(ROOT / 'scripts' / script, root / 'scripts')
        shutil.copy(ROOT / 'scripts/lib/lib-teamdb.sh', root / 'scripts/lib')
        with sqlite3.connect(root / '.opencode/context/team.db') as conn:
            conn.executescript((ROOT / 'sql/project-schema.sql').read_text())
        return root

    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory()
        self.addCleanup(self.tmp.cleanup)
        self.alice = self.project('alice')
        self.bob = self.project('bob')

    def db(self, project):
        return sqlite3.connect(project / '.opencode/context/team.db')

    def run_script(self, project, script, *args):
        return subprocess.run(['bash', str(project / 'scripts' / script), str(project), *args],
                              capture_output=True, text=True)

    def add_concept(self, project, slug, body, ts='2026-09-01 10:00:00', concept_id=None):
        with self.db(project) as conn:
            conn.execute('INSERT INTO concepts (id,slug,title,body_md,category,updated_at) VALUES (?,?,?,?,?,?)',
                         (concept_id, slug, slug.title(), body, 'core', ts))

    def share(self, source, target):
        dump = self.run_script(source, 'teamdb-dump.sh')
        self.assertEqual(dump.returncode, 0, dump.stderr)
        shutil.copy(source / 'db/teamdb/team.dump.sql', target / 'db/teamdb/team.dump.sql')
        return self.run_script(target, 'teamdb-merge.sh')

    def test_dump_is_one_line_per_row_and_restores_byte_for_byte(self):
        self.add_concept(self.alice, 'auth', BODY)
        self.run_script(self.alice, 'teamdb-dump.sh')
        lines = [l for l in (self.alice / 'db/teamdb/team.dump.sql').read_text().splitlines()
                 if not l.startswith('--')]
        self.assertEqual(len(lines), 1, lines)
        (self.bob / '.opencode/context/team.db').unlink()
        shutil.copy(self.alice / 'db/teamdb/team.dump.sql', self.bob / 'db/teamdb/team.dump.sql')
        restore = self.run_script(self.bob, 'teamdb-restore.sh')
        self.assertEqual(restore.returncode, 0, restore.stderr)
        with self.db(self.bob) as conn:
            self.assertEqual(conn.execute("SELECT body_md FROM concepts WHERE slug='auth'").fetchone()[0], BODY)

    def test_multiline_memory_reaches_the_other_machine(self):
        self.add_concept(self.alice, 'auth', BODY)
        merge = self.share(self.alice, self.bob)
        self.assertEqual(merge.returncode, 0, merge.stderr)
        with self.db(self.bob) as conn:
            self.assertEqual(conn.execute("SELECT body_md FROM concepts WHERE slug='auth'").fetchone()[0], BODY)

    def test_newer_remote_edit_wins_and_older_does_not(self):
        self.add_concept(self.alice, 'auth', BODY, ts='2026-09-02 10:00:00', concept_id=1)
        self.add_concept(self.bob, 'auth', 'vieja\nversión', ts='2026-09-01 10:00:00', concept_id=1)
        self.assertEqual(self.share(self.alice, self.bob).returncode, 0)
        with self.db(self.bob) as conn:
            self.assertEqual(conn.execute('SELECT body_md FROM concepts WHERE id=1').fetchone()[0], BODY)
        self.assertEqual(self.share(self.project('carol'), self.bob).returncode, 0)
        with self.db(self.bob) as conn:
            self.assertEqual(conn.execute('SELECT body_md FROM concepts WHERE id=1').fetchone()[0], BODY)

    def test_legacy_multiline_dump_still_merges(self):
        legacy = ('-- teamdb dump v1\n'
                  'INSERT INTO "concepts" ("id","slug","title","body_md","category","has_ui","updated_at") '
                  "VALUES (7,'legacy','Legacy','línea 1\nlínea ''2''\n','core',0,'2026-09-01 10:00:00');\n")
        (self.bob / 'db/teamdb/team.dump.sql').write_text(legacy)
        merge = self.run_script(self.bob, 'teamdb-merge.sh')
        self.assertEqual(merge.returncode, 0, merge.stderr)
        with self.db(self.bob) as conn:
            self.assertEqual(conn.execute('SELECT body_md FROM concepts WHERE id=7').fetchone()[0], "línea 1\nlínea '2'\n")

    def test_same_id_created_on_two_machines_keeps_both_entities(self):
        # Alice y Bob crean ambos el concepto id=5. Antes se pisaba uno.
        self.add_concept(self.alice, 'cache', 'de alice', ts='2026-09-05 10:00:00', concept_id=5)
        self.add_concept(self.bob, 'auth', 'de bob', ts='2026-09-01 10:00:00', concept_id=5)
        merge = self.share(self.alice, self.bob)
        self.assertEqual(merge.returncode, 0, merge.stderr)
        with self.db(self.bob) as conn:
            rows = dict(conn.execute('SELECT slug, body_md FROM concepts').fetchall())
            self.assertEqual(rows, {'auth': 'de bob', 'cache': 'de alice'})
            self.assertEqual(conn.execute("SELECT id FROM concepts WHERE slug='auth'").fetchone()[0], 5)

    def test_children_follow_their_remapped_parent(self):
        # Plan y tareas de Alice con ids que Bob ya usa: las tareas deben
        # colgar del plan de Alice (id nuevo en Bob), no del plan de Bob.
        with self.db(self.alice) as conn:
            conn.execute("INSERT INTO plans (id, slug, title) VALUES (1, 'login', 'Login')")
            conn.execute("INSERT INTO tasks (id, plan_id, slug, title) VALUES (1, 1, 't-1', 'Formulario')")
            conn.execute("INSERT INTO tasks (id, plan_id, slug, title) VALUES (2, 1, 't-2', 'Sesión')")
            conn.execute("INSERT INTO task_dependencies (task_id, depends_on_task_id) VALUES (2, 1)")
        with self.db(self.bob) as conn:
            conn.execute("INSERT INTO plans (id, slug, title) VALUES (1, 'pagos', 'Pagos')")
            conn.execute("INSERT INTO tasks (id, plan_id, slug, title) VALUES (1, 1, 't-1', 'Checkout')")
        merge = self.share(self.alice, self.bob)
        self.assertEqual(merge.returncode, 0, merge.stderr)
        with self.db(self.bob) as conn:
            login = conn.execute("SELECT id FROM plans WHERE slug='login'").fetchone()[0]
            self.assertNotEqual(login, 1)
            tasks = conn.execute('SELECT slug, title FROM tasks WHERE plan_id=? ORDER BY slug', (login,)).fetchall()
            self.assertEqual(tasks, [('t-1', 'Formulario'), ('t-2', 'Sesión')])
            self.assertEqual(conn.execute("SELECT title FROM tasks WHERE plan_id=1").fetchall(), [('Checkout',)])
            dep = conn.execute('SELECT t.title, d.title FROM task_dependencies x JOIN tasks t ON t.id=x.task_id '
                               'JOIN tasks d ON d.id=x.depends_on_task_id').fetchall()
            self.assertEqual(dep, [('Sesión', 'Formulario')])

    def test_merging_the_same_dump_twice_changes_nothing(self):
        self.add_concept(self.alice, 'auth', BODY)
        with self.db(self.alice) as conn:
            conn.execute("INSERT INTO routing_decisions (ts, user_intent, chosen_route) VALUES ('2026-09-01 10:00:00', 'login', 'SDD')")
        self.assertEqual(self.share(self.alice, self.bob).returncode, 0)
        first = self.run_script(self.bob, 'teamdb-merge.sh')
        self.assertEqual(first.returncode, 0, first.stderr)
        self.assertIn('0 insertadas', first.stdout)
        with self.db(self.bob) as conn:
            self.assertEqual(conn.execute('SELECT count(*) FROM routing_decisions').fetchone()[0], 1)
            self.assertEqual(conn.execute('SELECT count(*) FROM concepts').fetchone()[0], 1)

    def test_dump_values_cannot_run_sql_on_merge(self):
        hostile = ('INSERT INTO "concepts" ("id","slug","title","body_md","category","has_ui","updated_at") '
                   "VALUES (9,'x','x',(SELECT group_concat(name) FROM sqlite_master),'core',0,'2026-09-01');\n")
        (self.bob / 'db/teamdb/team.dump.sql').write_text(hostile)
        merge = self.run_script(self.bob, 'teamdb-merge.sh')
        self.assertNotEqual(merge.returncode, 0)
        with self.db(self.bob) as conn:
            self.assertIsNone(conn.execute('SELECT 1 FROM concepts WHERE id=9').fetchone())

    def test_decision_status_and_preference_changes_reach_the_other_clone(self):
        # Auditoría externa v0.12.0 #5: la decisión marcada superseded y la
        # preferencia editada en un clon no llegaban al otro (sin updated_at).
        with self.db(self.alice) as conn:
            conn.execute("INSERT INTO decisions (slug,title,body_md,status) VALUES ('orm','ORM','Usar Prisma','accepted')")
            conn.execute("INSERT INTO preferences (slug,scope,body_md) VALUES ('tono','global','Formal')")
            conn.execute("INSERT INTO known_problems (slug,title,symptom_md,status) VALUES ('flaky','Flaky','CI intermitente','open')")
        self.assertEqual(self.share(self.alice, self.bob).returncode, 0)
        with self.db(self.alice) as conn:
            conn.execute("UPDATE decisions SET body_md='Reemplazado por Drizzle', status='superseded' WHERE slug='orm'")
            conn.execute("UPDATE preferences SET body_md='Cercano' WHERE slug='tono'")
            conn.execute("UPDATE known_problems SET status='resolved' WHERE slug='flaky'")
        merge = self.share(self.alice, self.bob)
        self.assertEqual(merge.returncode, 0, merge.stderr)
        with self.db(self.bob) as conn:
            self.assertEqual(conn.execute("SELECT body_md, status FROM decisions WHERE slug='orm'").fetchone(),
                             ('Reemplazado por Drizzle', 'superseded'))
            self.assertEqual(conn.execute("SELECT body_md FROM preferences WHERE slug='tono'").fetchone()[0], 'Cercano')
            self.assertEqual(conn.execute("SELECT status FROM known_problems WHERE slug='flaky'").fetchone()[0], 'resolved')
        # Converge: volver a mezclar no cambia nada ni reporta conflictos.
        again = self.run_script(self.bob, 'teamdb-merge.sh')
        self.assertEqual(again.returncode, 0, again.stderr)
        self.assertIn('0 actualizadas', again.stdout)
        self.assertNotIn('CONFLICTO', again.stdout)

    def test_concurrent_edits_keep_the_newest_and_report_the_conflict(self):
        with self.db(self.alice) as conn:
            conn.execute("INSERT INTO decisions (slug,title,body_md) VALUES ('api','API','REST')")
        self.assertEqual(self.share(self.alice, self.bob).returncode, 0)
        with self.db(self.alice) as conn:
            conn.execute("UPDATE decisions SET body_md='GraphQL' WHERE slug='api'")
        with self.db(self.bob) as conn:        # Bob edita después: su versión es la más nueva
            conn.execute("UPDATE decisions SET body_md='gRPC' WHERE slug='api'")
        merge = self.share(self.alice, self.bob)
        self.assertEqual(merge.returncode, 0, merge.stderr)
        self.assertIn('CONFLICTO resuelto por versión: decisions/api: se conserva la versión local', merge.stdout)
        with self.db(self.bob) as conn:
            self.assertEqual(conn.execute("SELECT body_md FROM decisions WHERE slug='api'").fetchone()[0], 'gRPC')
        back = self.share(self.bob, self.alice)
        self.assertEqual(back.returncode, 0, back.stderr)
        self.assertIn('gana la versión remota', back.stdout)
        with self.db(self.alice) as conn:
            self.assertEqual(conn.execute("SELECT body_md FROM decisions WHERE slug='api'").fetchone()[0], 'gRPC')


if __name__ == '__main__':
    unittest.main()
