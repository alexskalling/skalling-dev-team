"""Dos integrantes editan la misma memoria en ramas distintas y convergen.

Auditoría de c7517ea (P1): con merge=union (el que instala setup.sh), el dump
fusionado tenía el Cambio A (11:00) y el Cambio B (12:00), pero la versión
viajaba en filas aparte de memory_versions: el merge le asignaba 12:00 a
ambos contenidos, aplicaba A y descartaba B como "misma versión". TeamDB
quedaba con A fechado a las 12:00 y todo salía con código 0.
"""
import os
import sqlite3
import subprocess
import tempfile
import time
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
ENV = {**os.environ, 'SKALLING_ROOT': str(ROOT), 'GIT_AUTHOR_NAME': 't', 'GIT_AUTHOR_EMAIL': 't@t',
       'GIT_COMMITTER_NAME': 't', 'GIT_COMMITTER_EMAIL': 't@t'}
ENV.pop('SKALLING_RUNTIME_AGENT', None)


class MergeAcrossBranches(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory()
        self.addCleanup(self.tmp.cleanup)
        base = Path(self.tmp.name)
        self.origin = base / 'origin.git'
        self.git(base, 'init', '-q', '--bare', '-b', 'main', str(self.origin))
        self.alice = self.clone(base / 'alice')
        (self.alice / '.gitattributes').write_text('db/teamdb/team.dump.sql merge=union\n')
        (self.alice / '.gitignore').write_text('.opencode/\n')
        self.script('teamdb-init.sh', self.alice)
        self.memory(self.alice, 'decision', 'api', 'API', 'REST')
        self.publish(self.alice, 'memoria inicial')
        self.bob = self.clone(base / 'bob')
        self.script('teamdb-init.sh', self.bob)   # clon nuevo: restaura desde el dump
        # teamdb-init tomaba el lock y el restore esperaba el mismo: un clon
        # nuevo nunca restauraba la memoria del equipo.
        self.assertEqual(self.state(self.bob)[0], 'REST')

    def git(self, cwd, *args):
        return subprocess.run(['git', *args], cwd=cwd, env=ENV, capture_output=True, text=True, check=True)

    def clone(self, path):
        self.git(path.parent, 'clone', '-q', str(self.origin), str(path))
        return path

    def script(self, name, project, *args, check=True):
        result = subprocess.run(['bash', str(ROOT / 'scripts' / name), str(project), *args],
                                env=ENV, capture_output=True, text=True)
        if check:
            self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
        return result

    def memory(self, project, *args):
        result = subprocess.run(['bash', str(ROOT / 'scripts/teamdb-memory.sh'), '--project', str(project), *args],
                                env=ENV, capture_output=True, text=True)
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)

    def publish(self, project, message):
        self.script('teamdb-dump.sh', project)
        self.git(project, 'add', '-A')
        self.git(project, 'commit', '-qm', message)
        self.git(project, 'push', '-q', 'origin', 'HEAD:main')

    def state(self, project):
        with sqlite3.connect(project / '.opencode/context/team.db') as conn:
            body = conn.execute("SELECT body_md FROM decisions WHERE slug='api'").fetchone()[0]
            version = conn.execute("SELECT updated_at FROM memory_versions WHERE table_name='decisions' AND slug='api'").fetchone()[0]
        return body, version

    def test_both_clones_converge_to_the_newest_change(self):
        self.memory(self.alice, 'decision', 'api', 'API', 'Cambio A')      # 11:00
        self.publish(self.alice, 'cambio A')
        time.sleep(0.05)
        self.memory(self.bob, 'decision', 'api', 'API', 'Cambio B')        # 12:00
        self.script('teamdb-dump.sh', self.bob)
        self.git(self.bob, 'add', '-A')
        self.git(self.bob, 'commit', '-qm', 'cambio B')
        self.git(self.bob, 'pull', '-q', '--no-rebase', '--no-edit', 'origin', 'main')   # merge=union real
        merge_commit = self.git(self.bob, 'rev-parse', 'HEAD').stdout.strip()
        dump = (self.bob / 'db/teamdb/team.dump.sql').read_text()
        self.assertIn('Cambio A', dump)
        self.assertIn('Cambio B', dump)
        self.script('teamdb-merge.sh', self.bob)
        bob = self.state(self.bob)
        self.assertEqual(bob[0], 'Cambio B')
        self.git(self.bob, 'add', '-A')
        self.git(self.bob, 'commit', '-qm', 'memoria fusionada', '--allow-empty')
        self.git(self.bob, 'push', '-q', 'origin', 'HEAD:main')
        self.git(self.alice, 'pull', '-q', '--no-rebase', '--no-edit', 'origin', 'main')
        self.script('teamdb-merge.sh', self.alice)
        self.assertEqual(self.state(self.alice), bob, 'las dos copias deben tener el mismo contenido y versión')
        # Tercera auditoría: Carol clona desde cero el commit del merge (dump con
        # las dos filas, la vieja al final) y debe recibir la memoria vigente.
        carol = self.clone(Path(self.tmp.name) / 'carol')
        self.git(carol, 'checkout', '-q', merge_commit)
        self.assertIn('Cambio A', (carol / 'db/teamdb/team.dump.sql').read_text())
        self.script('teamdb-init.sh', carol)
        self.assertEqual(self.state(carol), bob, 'un clon nuevo debe restaurar la versión más nueva')

    def test_same_version_with_different_content_is_an_explicit_conflict(self):
        self.memory(self.alice, 'decision', 'api', 'API', 'Cambio A')
        self.script('teamdb-dump.sh', self.alice)
        dump = (self.alice / 'db/teamdb/team.dump.sql').read_text()
        (self.bob / 'db/teamdb/team.dump.sql').write_text(dump.replace('Cambio A', 'Cambio C'))
        self.script('teamdb-merge.sh', self.bob)                              # bob adopta C con la versión de A
        (self.bob / 'db/teamdb/team.dump.sql').write_text(dump)               # llega A con la MISMA versión
        result = self.script('teamdb-merge.sh', self.bob, check=False)
        self.assertEqual(result.returncode, 3, result.stdout + result.stderr)
        self.assertIn('CONFLICTO SIN RESOLVER', result.stderr)
        self.assertEqual(self.state(self.bob)[0], 'Cambio C')


if __name__ == '__main__':
    unittest.main()
