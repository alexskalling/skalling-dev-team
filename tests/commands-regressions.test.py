"""Command failures reproduced against disposable projects, without providers."""
from contextlib import closing
import json
import os
from pathlib import Path
import sqlite3
import subprocess
import sys
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[1]


class CommandRegressions(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory(prefix='skalling-commands-')
        self.addCleanup(self.tmp.cleanup)
        self.base = Path(self.tmp.name)
        self.project = self.base/'project'
        self.project.mkdir()
        (self.project/'README.md').write_text('# Product\nService for sending campaigns.\n')
        self.bin = self.base/'bin'
        self.bin.mkdir()
        self.env = {**os.environ, 'HOME': str(self.base/'home'),
                    'SKALLING_OPENCODE_DIR': str(self.base/'global'),
                    'PATH': str(self.bin)+os.pathsep+os.environ['PATH']}
        Path(self.env['HOME']).mkdir()
        self.stub('opencode', 'echo 2.0.21')

    def stub(self, name, body):
        path = self.bin/name
        path.write_text('#!/bin/sh\n'+body+'\n')
        path.chmod(0o755)

    def run_script(self, name, *args, cwd=None):
        path = ROOT/name
        return subprocess.run([sys.executable if path.suffix == '.py' else 'bash', str(path), *map(str, args)],
                              cwd=cwd or self.project, env=self.env, stdin=subprocess.DEVNULL,
                              capture_output=True, text=True, timeout=30)

    def init_db(self):
        result = self.run_script('scripts/teamdb-init.sh', self.project)
        self.assertEqual(result.returncode, 0, result.stderr)
        return self.project/'.opencode/context/team.db'

    def test_related_omitted_type_uses_the_supplied_project(self):
        db = self.init_db()
        with closing(sqlite3.connect(db)) as conn, conn:
            conn.execute("INSERT INTO concepts(slug,title,updated_at) VALUES('topic','Topic',datetime('now'))")
        result = self.run_script('scripts/teamdb-related.sh', 'topic', self.project, cwd=self.base)
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertIn("'topic' (concept)", result.stdout)

    def test_init_rejects_home_alias_and_nonproject_before_writing(self):
        home = Path(self.env['HOME'])
        alias = self.base/'alias'
        alias.symlink_to(home, target_is_directory=True)
        empty = self.base/'empty'; empty.mkdir()
        for target in (home, alias, empty):
            result = self.run_script('bootstrap-context.sh', '--target', target, '--install-project')
            self.assertNotEqual(result.returncode, 0)
            self.assertEqual(list(target.iterdir()), [], result.stdout+result.stderr)

    def test_init_preflight_rejects_version_and_missing_checkout_without_mutation(self):
        self.stub('opencode', 'echo 1.99.0')
        before = sorted(p.name for p in self.project.iterdir())
        result = self.run_script('bootstrap-context.sh', '--target', self.project, '--install-project')
        self.assertNotEqual(result.returncode, 0)
        self.assertIn('no está soportado', result.stdout+result.stderr)
        self.assertEqual(sorted(p.name for p in self.project.iterdir()), before)
        self.stub('opencode', 'echo 2.0.21')
        installed = self.base/'installed'; installed.mkdir()
        (installed/'bootstrap-context.sh').write_bytes((ROOT/'bootstrap-context.sh').read_bytes())
        (installed/'scripts').symlink_to(ROOT/'scripts', target_is_directory=True)
        result = self.run_script(installed/'bootstrap-context.sh', '--target', self.project, '--install-project')
        self.assertNotEqual(result.returncode, 0)
        self.assertIn('Falta el checkout', result.stderr)
        self.assertEqual(sorted(p.name for p in self.project.iterdir()), before)

    def test_project_resolves_git_root_but_codegraph_rejects_temporary_workspace(self):
        subprocess.run(['git', '-C', str(self.project), 'init', '-q'], check=True)
        subdir = self.project/'src'; subdir.mkdir()
        result = self.run_script('scripts/skalling-project-root.py', subdir)
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(Path(result.stdout.strip()), self.project.resolve())
        self.stub('codegraph', f'touch "{self.base}/index-called"')
        result = self.run_script('scripts/skalling-codegraph.sh', self.project)
        self.assertNotEqual(result.returncode, 0)
        self.assertFalse((self.base/'index-called').exists())

    def test_coverage_timeout_and_invalid_artifact_are_recorded(self):
        db = self.init_db()
        yaml = self.project/'.opencode/project.yaml'
        yaml.write_text('testing:\n  timeout_seconds: 1\n  coverage:\n    available: true\n    command: "sleep 10"\n')
        result = self.run_script('scripts/skalling-coverage.sh', self.project)
        self.assertEqual(result.returncode, 124, result.stdout+result.stderr)
        with closing(sqlite3.connect(db)) as conn:
            row = conn.execute('SELECT format,percent,note FROM coverage_runs').fetchone()
        self.assertEqual(row[:2], ('timeout', None))
        self.assertIn('1 segundos', row[2])
        yaml.write_text('testing:\n  coverage:\n    available: true\n    command: "echo invalid > coverage.json"\n')
        result = self.run_script('scripts/skalling-coverage.sh', self.project)
        self.assertEqual(result.returncode, 0, result.stdout+result.stderr)
        with closing(sqlite3.connect(db)) as conn:
            self.assertEqual(conn.execute('SELECT format,percent FROM coverage_runs ORDER BY id DESC LIMIT 1').fetchone(), ('invalid', None))

    def test_update_authorized_noninteractive_invocation(self):
        repo = self.base/'repo'; (repo/'.git').mkdir(parents=True)
        self.stub('git', '''case "$1" in
fetch) exit 0;;
tag) echo v99.0.0;;
merge-base) exit 1;;
rev-list) echo 1;;
log) echo 'fixture release';;
diff) echo '+fixture changelog';;
*) exit 9;;
esac''')
        result = self.run_script('scripts/update.sh', '--repo', repo, '--yes', '--dry-run')
        self.assertEqual(result.returncode, 0, result.stdout+result.stderr)
        self.assertNotIn('¿Procedo', result.stdout)
        self.assertIn('update.sh" --yes', (ROOT/'command/skalling-update.md').read_text())


if __name__ == '__main__':
    unittest.main()
