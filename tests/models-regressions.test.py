"""Regression cases for validation, project resolution and failed publication."""
import importlib.util
import json
import os
from pathlib import Path
import stat
import subprocess
import sys
import tempfile
import unittest
from unittest.mock import patch

ROOT = Path(__file__).resolve().parents[1]
spec = importlib.util.spec_from_file_location('models', ROOT/'scripts/skalling_models.py')
models = importlib.util.module_from_spec(spec)
spec.loader.exec_module(models)


class Models(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory(prefix='skalling-models-regression-')
        self.addCleanup(self.tmp.cleanup)
        self.base = Path(self.tmp.name).resolve()
        self.config = self.base/'config'
        self.project = self.base/'project'
        self.sub = self.project/'src/nested'
        self.sub.mkdir(parents=True)
        self.global_agent = self.config/'agents/Alex.md'
        self.local_agent = self.project/'.opencode/agents/Alex.md'
        original = '---\ndescription: Fixture\nmodel: fixture/old\npermission:\n  bash: ask\n---\nKeep my prompt.\n'
        for file in (self.global_agent, self.local_agent):
            file.parent.mkdir(parents=True)
            file.write_text(original)
            file.chmod(0o640)
        self.overrides = self.config/'model-overrides.json'
        self.overrides.write_text('{"Alex":"fixture/old"}\n')
        self.env = {**os.environ, 'SKALLING_OPENCODE_DIR': str(self.config)}
        self.env.pop('SKALLING_PROJECT_DIR', None)

    def run_command(self, *args, cwd=None):
        return subprocess.run(['bash', str(ROOT/'scripts/skalling-models.sh'), *args],
                              cwd=cwd or self.sub, env=self.env, capture_output=True, text=True, timeout=20)

    def snapshot(self):
        return {p: (p.read_bytes(), stat.S_IMODE(p.stat().st_mode))
                for p in (self.global_agent, self.local_agent, self.overrides) if p.exists()}

    def test_invalid_ids_leave_all_assignments_unchanged(self):
        before = self.snapshot()
        for model in ('missing-provider', 'provider/', '/model', 'provider/model name',
                      'provider/model\npermission: allow', 'provider/model\n', 'provider/model#'):
            with self.subTest(model=model):
                result = self.run_command('set', 'Alex', model)
                self.assertNotEqual(result.returncode, 0, result.stdout)
                self.assertEqual(self.snapshot(), before)

    def test_nested_git_and_nongit_projects_update_and_show_both_agents(self):
        for use_git in (False, True):
            if use_git:
                subprocess.run(['git','-C',str(self.project),'init','-q'],check=True)
            result = self.run_command('set', 'Alex', 'fixture/chosen#high')
            self.assertEqual(result.returncode, 0, result.stderr)
            for path in (self.global_agent, self.local_agent):
                self.assertIn('model: fixture/chosen#high', path.read_text())
                self.assertTrue(path.read_text().endswith('Keep my prompt.\n'))
                self.assertIn('  bash: ask', path.read_text())
                self.assertEqual(stat.S_IMODE(path.stat().st_mode), 0o640)
            shown = self.run_command('show')
            self.assertIn('proyecto=fixture/chosen#high', shown.stdout)
            reset = self.run_command('reset', 'Alex')
            self.assertEqual(reset.returncode, 0, reset.stderr)
            self.assertNotIn('model:', self.local_agent.read_text())

    def test_malformed_later_agent_prevents_set_reset_and_apply(self):
        self.local_agent.write_text('---\nmalformed header\n')
        before = self.snapshot()
        for args in (('set','Alex','fixture/new'), ('reset','Alex'), ('apply',)):
            with self.subTest(args=args):
                result = self.run_command(*args)
                self.assertNotEqual(result.returncode, 0)
                self.assertIn('Frontmatter', result.stderr)
                self.assertEqual(self.snapshot(), before)

    def test_invalid_saved_models_and_missing_agent_fail_before_writing(self):
        self.overrides.write_text('{"Alex":"invalid"}')
        before = self.snapshot()
        result = self.run_command('apply')
        self.assertNotEqual(result.returncode, 0)
        self.assertEqual(self.snapshot(), before)
        self.global_agent.unlink()
        before = self.snapshot()
        result = self.run_command('set', 'Alex', 'fixture/new')
        self.assertNotEqual(result.returncode, 0)
        self.assertEqual(self.snapshot(), before)

    def test_apply_explicit_subfolder_uses_project_root_without_rewriting_json(self):
        self.overrides.write_text('{ "Alex": "fixture/new" }\n')
        original = self.overrides.read_bytes()
        result = self.run_command('apply', '--project', str(self.sub), cwd=self.base)
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertIn('model: fixture/new', self.local_agent.read_text())
        self.assertEqual(self.overrides.read_bytes(), original)

    def test_publish_error_rolls_back_previous_replacements(self):
        before = self.snapshot()
        real_replace = os.replace
        for failed_target in (self.local_agent, self.overrides):
            failed = False
            def fail_once(src, dest):
                nonlocal failed
                if Path(dest) == failed_target and not failed:
                    failed = True
                    raise OSError('synthetic disk failure')
                return real_replace(src, dest)
            with patch.object(models.os, 'replace', side_effect=fail_once):
                with self.assertRaisesRegex(OSError, 'synthetic disk failure'):
                    models.change(self.config, self.project, 'set', ['Alex','fixture/new'])
            self.assertTrue(failed)
            self.assertEqual(self.snapshot(), before)
            self.assertEqual(list(self.base.rglob('.models-*')), [])

    def test_staging_error_and_absent_json_do_not_publish_changes(self):
        self.overrides.unlink()
        before = self.snapshot()
        original = models.staged_file
        def fail_local(path, contents, mode):
            if path == self.local_agent:
                raise OSError('staging denied')
            return original(path, contents, mode)
        with patch.object(models, 'staged_file', side_effect=fail_local):
            with self.assertRaisesRegex(OSError, 'staging denied'):
                models.change(self.config, self.project, 'set', ['Alex','fixture/new'])
        self.assertEqual(self.snapshot(), before)
        self.assertFalse(self.overrides.exists())
        self.assertEqual(list(self.base.rglob('.models-*')), [])

    def test_concurrent_assignments_preserve_both_models(self):
        (self.config/'agents/Teo.md').write_bytes(self.global_agent.read_bytes())
        processes = [subprocess.Popen(['bash',str(ROOT/'scripts/skalling-models.sh'),'set',name,model],
                                     cwd=self.sub, env=self.env, stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True)
                     for name,model in [('Alex','fixture/one'),('Teo','fixture/two')]]
        for process in processes:
            out, err = process.communicate(timeout=20)
            self.assertEqual(process.returncode, 0, out+err)
        self.assertEqual(json.loads(self.overrides.read_text()), {'Alex':'fixture/one','Teo':'fixture/two'})


if __name__ == '__main__':
    unittest.main()
