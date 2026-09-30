"""User-visible command outcomes against disposable projects, without providers."""
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


class CommandsTest(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory()
        self.addCleanup(self.tmp.cleanup)
        self.project = Path(self.tmp.name) / 'project'
        self.project.mkdir()
        env_patch = patch.dict(os.environ, {'SKALLING_OPENCODE_DIR': str(Path(self.tmp.name)/'global'),
                                          'AGENTS_SKILLS_DIR': str(Path(self.tmp.name)/'personal')})
        env_patch.start()
        self.addCleanup(env_patch.stop)
        self.db = self.project / '.opencode/context/team.db'
        self.db.parent.mkdir(parents=True)
        with sqlite3.connect(self.db) as conn:
            conn.executescript((ROOT / 'sql/project-schema.sql').read_text())

    def command(self, name, *args):
        return subprocess.run(['bash', str(ROOT / 'scripts' / name), *map(str, args)],
                              text=True, capture_output=True, timeout=30)

    def test_status_and_dashboard_show_current_objective(self):
        body = {'id': 'current', 'state': 'implementation_ready', 'intent': 'Alinear tabla',
                'outcomes': [{'id': 'one', 'expected': 'Columnas alineadas'}]}
        with sqlite3.connect(self.db) as conn:
            conn.execute('INSERT INTO agent_workflows VALUES (?,?)', ('current', json.dumps(body)))
        result = self.command('teamdb-status.sh', '', self.project)
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertIn('Alinear tabla', result.stdout)
        spec = importlib.util.spec_from_file_location('dashboard', ROOT / 'scripts/dashboard-server.py')
        dashboard = importlib.util.module_from_spec(spec)
        spec.loader.exec_module(dashboard)
        overview = dashboard.DashboardData(self.db).overview()
        self.assertEqual(overview['workflows'][0]['intent'], 'Alinear tabla')
        self.assertIsNone(overview['progress']['percent'])

    def test_memory_review_checks_database(self):
        with sqlite3.connect(self.db) as conn:
            for slug in ('one', 'two'):
                conn.execute("INSERT INTO concepts(slug,title,body_md,category,updated_at) "
                             "VALUES (?,'Same','identical body','architecture',datetime('now'))", (slug,))
        result = self.command('mem-review.sh', '--target', self.project, '--dry-run')
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertIn('one', result.stdout)
        self.assertIn('two', result.stdout)

    def test_merge_reports_dump_and_root_instructions(self):
        subprocess.run(['git', 'init', '-q', str(self.project)], check=True)
        sha = subprocess.run(['git', '-C', str(self.project), 'hash-object', '-w', '--stdin'],
                             input='sample\n', text=True, capture_output=True, check=True).stdout.strip()
        (self.project / '.git/MERGE_HEAD').write_text(sha + '\n')
        paths = ['AGENTS.md', 'db/teamdb/team.dump.sql']
        index = ''.join(f'100644 {sha} {stage}\t{path}\n' for path in paths for stage in (1, 2, 3))
        subprocess.run(['git', '-C', str(self.project), 'update-index', '--index-info'],
                       input=index, text=True, check=True)
        result = self.command('merge-helper.sh', '--target', self.project)
        for path in paths:
            self.assertIn(path, result.stdout)
        self.assertNotIn('Sin conflictos', result.stdout)

    def test_skill_reconciliation_removes_stale_and_preserves_custom(self):
        from skalling_skills import inventory, sync_registry, metadata
        skill = self.project / '.opencode/skills/custom/SKILL.md'
        skill.parent.mkdir(parents=True)
        skill.write_text('---\nname: custom\ndescription: Custom skill\n---\n')
        sync_registry(self.db, inventory(skill.parent.parent), global_db=False)
        with sqlite3.connect(self.db) as conn:
            self.assertEqual(conn.execute('SELECT name FROM skills_registry').fetchall(), [('custom',)])
        skill.unlink()
        sync_registry(self.db, inventory(skill.parent.parent), global_db=False)
        with sqlite3.connect(self.db) as conn:
            self.assertEqual(conn.execute('SELECT count(*) FROM skills_registry').fetchone()[0], 0)
        skill.write_text('---\nname: custom\ndescription: Bad: YAML\n---\n')
        with self.assertRaises(ValueError):
            metadata(skill)

    def test_refresh_repairs_core_and_preserves_custom(self):
        from skalling_skills import repair, inventory, sync_registry, audit
        target = self.project / '.opencode'
        repair(ROOT, target)
        custom = target / 'skills/brainstorming/SKILL.md'
        custom.write_text(custom.read_text() + '\nPersonal instruction.\n')
        missing = target / 'skills/systematic-debugging/SKILL.md'
        missing.unlink()
        preserved = repair(ROOT, target)
        self.assertIn('brainstorming', preserved)
        self.assertTrue(custom.read_text().endswith('Personal instruction.\n'))
        self.assertTrue(missing.is_file())
        sync_registry(self.db, inventory(target / 'skills'))
        (self.project / 'package.json').write_text(json.dumps({'dependencies': {'next': '16', 'react': '19'}, 'devDependencies': {'vitest': '3'}}))
        report = audit(ROOT, self.project)
        self.assertTrue(report['ready'], report)
        self.assertIn('vitest', {r['name'] for r in report['recommendations']})
        self.assertFalse((target / 'skills/vitest').exists())
        missing.write_text('---\nname: systematic-debugging\ndescription: Bad: YAML\n---\n')
        report = audit(ROOT, self.project)
        self.assertFalse(report['ready'])
        self.assertTrue(report['invalid'])

    def test_corrupt_workflow_is_not_reported_as_idle(self):
        with sqlite3.connect(self.db) as conn:
            conn.execute('INSERT INTO agent_workflows VALUES (?,?)', ('broken', '{bad'))
        result = self.command('teamdb-status.sh', '', self.project)
        self.assertNotEqual(result.returncode, 0)
        self.assertNotIn('no plans', result.stdout)

    def test_coverage_honors_availability_and_field_order(self):
        yaml = self.project / '.opencode/project.yaml'
        yaml.write_text('testing:\n  coverage:\n    command: "exit 9"\n    available: false\n')
        result = self.command('skalling-coverage.sh', self.project)
        self.assertNotEqual(result.returncode, 0)
        self.assertNotIn('Corriendo:', result.stdout)
        yaml.write_text('testing:\n  coverage:\n    command: "exit 9"\n    available: true\n')
        result = self.command('skalling-coverage.sh', self.project)
        self.assertNotEqual(result.returncode, 0)
        self.assertIn('Corriendo: exit 9', result.stdout)
        with sqlite3.connect(self.db) as conn:
            self.assertEqual(conn.execute('SELECT count(*) FROM coverage_runs').fetchone()[0], 0)

    def test_external_privacy_reports_and_blocks_tracked_memory(self):
        subprocess.run(['git', 'init', '-q', str(self.project)], check=True)
        tracked = self.project / '.opencode/project.yaml'
        tracked.write_text('schema: skalling-project-v1\n')
        subprocess.run(['git', '-C', str(self.project), 'add', '.opencode/project.yaml'], check=True)
        result = self.command('skalling-privacy.sh', 'external', self.project)
        self.assertEqual(result.returncode, 3, result.stdout + result.stderr)
        result = self.command('skalling-privacy.sh', 'status', self.project)
        self.assertEqual(result.returncode, 3)
        gate = subprocess.run([sys.executable, str(ROOT/'scripts/hooks/git-gate.py'), 'pre-commit'],
                              cwd=self.project, capture_output=True, text=True)
        self.assertNotEqual(gate.returncode, 0)
        self.assertIn('Privacidad externa incompleta', gate.stderr)

    def test_runtime_detects_modified_and_missing_installed_helpers(self):
        target = self.project / '.opencode'
        script = target / 'scripts/example.py'
        script.parent.mkdir(parents=True)
        script.write_text('original')
        import shutil
        required = ('scripts/skalling-workflow.py', 'scripts/skalling_skills.py',
                    'scripts/skalling-refresh.sh', 'plugins/skalling-workflow.js',
                    'plugins/skalling-git-guard.js')
        for name in (*required, *(str(p.relative_to(ROOT)) for p in (ROOT/'command').glob('skalling-*.md'))):
            dest = target/name
            dest.parent.mkdir(parents=True, exist_ok=True)
            shutil.copyfile(ROOT/name, dest)
        (target/'hooks').mkdir()
        shutil.copyfile(ROOT/'scripts/hooks/git-gate.py', target/'hooks/git-gate.py')
        command = [sys.executable, str(ROOT/'scripts/skalling-runtime.py')]
        args = ['--root', str(ROOT), '--target', str(target)]
        subprocess.run(command + ['record'] + args, check=True, capture_output=True)
        result = subprocess.run(command + ['check'] + args, capture_output=True, text=True)
        self.assertEqual(result.returncode, 0, result.stdout)
        script.write_text('modified')
        result = subprocess.run(command + ['check'] + args, capture_output=True, text=True)
        self.assertEqual(result.returncode, 1)
        self.assertIn('example.py', result.stdout)
        script.unlink()
        result = subprocess.run(command + ['check'] + args, capture_output=True, text=True)
        self.assertEqual(result.returncode, 1)

        # Recording a broken installation must not certify it as complete.
        (target/'plugins/skalling-workflow.js').unlink()
        subprocess.run(command + ['record'] + args, check=True, capture_output=True)
        result = subprocess.run(command + ['check'] + args, capture_output=True, text=True)
        self.assertEqual(result.returncode, 1)
        self.assertIn('plugins/skalling-workflow.js', result.stdout)


if __name__ == '__main__':
    unittest.main()
