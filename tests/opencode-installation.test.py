"""Installer boundary: version rejection, dry-run and local upgrade isolation."""
import os
from pathlib import Path
import subprocess
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[1]
RETIRED = ('plugins/skalling-execution-efficiency.js', 'plugins/skalling-goal.js', 'scripts/skalling-goal.sh',
           'scripts/skalling-goal.py', 'command/skalling-goal.md',
           'templates/okf/index.template.md', 'templates/changes/proposal.template.md', 'scripts/test-teamdb-safe.sh', 'scripts/test-teamdb-git-sync.sh')


class OpenCodeInstallation(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory(prefix='skalling-v2-install-')
        self.addCleanup(self.tmp.cleanup)
        self.base = Path(self.tmp.name)
        self.project = self.base / 'project'
        self.project.mkdir()
        self.config = self.base / 'config'
        self.bin = self.base / 'bin'
        self.bin.mkdir()
        self.version('2.0.21')
        stub = self.bin / 'gentle-ai'
        stub.write_text('#!/bin/sh\nexit 0\n')
        stub.chmod(0o755)
        self.env = dict(os.environ, HOME=str(self.base), SKALLING_OPENCODE_DIR=str(self.config),
                        SKALLING_DB_GLOBAL=str(self.config / 'team.db'),
                        PATH=f'{self.bin}:{os.environ["PATH"]}')

    def version(self, value, code=0):
        stub = self.bin / 'opencode'
        stub.write_text(f'#!/bin/sh\necho "{value}"\nexit {code}\n')
        stub.chmod(0o755)

    def run_installer(self, local=False, *flags):
        args = ['bash', str(ROOT / ('setup.sh' if local else 'install-global.sh'))]
        if local:
            args += ['--target', str(self.project)]
        return subprocess.run([*args, *flags], env=self.env, capture_output=True, text=True, timeout=90)

    def test_rejects_unsupported_or_unreadable_versions_without_mutation(self):
        for version, code in [('1.18.29',0), ('1.99.99',0), ('2.0.20',0), ('3.0.0',0), ('unknown',0), ('2.0.21',1)]:
            self.version(version, code)
            for local in (False, True):
                with self.subTest(version=version, local=local):
                    result = self.run_installer(local, '--force')
                    self.assertNotEqual(result.returncode, 0, result.stdout + result.stderr)
                    self.assertIn('2.0.21', result.stdout + result.stderr)
                    self.assertFalse(self.config.exists())
                    self.assertEqual(list(self.project.iterdir()), [])

    def seed(self, destination):
        for name in (*RETIRED, 'plugins/custom.js', 'templates/okf/custom.md'):
            path = destination / name
            path.parent.mkdir(parents=True, exist_ok=True)
            path.write_text('existing')

    def test_dry_run_preserves_retired_files(self):
        for local in (False, True):
            destination = self.project / '.opencode' if local else self.config
            self.seed(destination)
            (destination / 'agents').symlink_to(destination / 'missing-agents', target_is_directory=True)
            before = {str(p.relative_to(destination)): p.read_bytes()
                      for p in destination.rglob('*') if p.is_file()}
            result = self.run_installer(local, '--dry-run')
            self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
            after = {str(p.relative_to(destination)): p.read_bytes()
                     for p in destination.rglob('*') if p.is_file()}
            self.assertEqual(before, after)
            self.assertTrue((destination / 'agents').is_symlink())

    def test_local_upgrade_removes_retired_files_and_backs_them_up(self):
        destination = self.project / '.opencode'
        self.seed(destination)
        result = self.run_installer(True, '--force')
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
        for name in RETIRED:
            self.assertFalse((destination / name).exists(), name)
        self.assertEqual((destination / 'plugins/custom.js').read_text(), 'existing')
        self.assertEqual((destination / 'templates/okf/custom.md').read_text(), 'existing')
        self.assertTrue((destination / 'plugins/skalling-workflow.js').exists())
        import tarfile
        backups = list(self.project.rglob('*.tar.gz'))
        self.assertTrue(backups)
        with tarfile.open(backups[0]) as archive:
            self.assertTrue(any(n.endswith('plugins/skalling-goal.js') for n in archive.getnames()))


if __name__ == '__main__':
    unittest.main()
