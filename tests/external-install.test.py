"""External installs must leave tracked project bytes and the Git index alone."""
from pathlib import Path
import os
import sqlite3
import subprocess
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[1]


class ExternalInstall(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory(prefix='skalling-external-')
        self.addCleanup(self.tmp.cleanup)
        self.base = Path(self.tmp.name).resolve()
        self.project = self.base/'public-project'; self.project.mkdir()
        binary = self.base/'bin'; binary.mkdir()
        oc = binary/'opencode'; oc.write_text('#!/bin/sh\necho 2.2.5\n'); oc.chmod(0o755)
        self.env = {**os.environ, 'PATH': str(binary)+os.pathsep+os.environ['PATH'],
                    'SKALLING_OPENCODE_DIR': str(self.base/'global'), 'SKALLING_ROOT': str(ROOT),
                    'AGENTS_SKILLS_DIR': str(self.base/'skills'), 'GIT_CONFIG_GLOBAL': os.devnull,
                    'GIT_CONFIG_NOSYSTEM': '1'}
        self.git('init','-q')
        self.original = {'README.md': b'# Product\nPublic campaign service.\n',
                         '.gitignore': b'node_modules/\n', '.gitattributes': b'*.txt text\n',
                         'AGENTS.md': b'# Repository instructions\nKeep the existing conventions.\n'}
        for name, data in self.original.items():
            (self.project/name).write_bytes(data)
        self.git('add','.')
        self.git('-c','user.name=Test','-c','user.email=test@example.invalid','-c','commit.gpgsign=false','commit','-qm','Initial')

    def git(self, *args, check=True, input=None):
        return subprocess.run(['git','-C',str(self.project),*args],env=self.env,capture_output=True,text=True,
                              check=check,input=input,timeout=20)

    def script(self, script, *args, check=True):
        result = subprocess.run(['bash',str(ROOT/script),*map(str,args)],cwd=self.project,env=self.env,
                                stdin=subprocess.DEVNULL,capture_output=True,text=True,timeout=90)
        if check:
            self.assertEqual(result.returncode,0,result.stdout[-2500:]+result.stderr[-2500:])
        return result

    def assert_clean(self):
        for name, data in self.original.items():
            self.assertEqual((self.project/name).read_bytes(),data,name)
        self.git('add','-A')
        self.assertEqual(self.git('diff','--cached','--name-only').stdout,'')
        self.assertEqual(self.git('status','--porcelain').stdout,'')

    def test_full_init_and_local_update_stay_private(self):
        self.script('bootstrap-context.sh','--target',self.project,'--install-project','--privacy','external')
        self.assert_clean()
        self.assertEqual(len(list((self.project/'.opencode/agents').glob('*.md'))),8)
        self.assertFalse((self.project/'.codegraph').exists())
        self.assertIn('external',self.script('scripts/skalling-privacy.sh','status',self.project).stdout)
        self.script('scripts/update.sh','--local-only','--project',self.project,'--yes')
        self.assert_clean()
        self.script('scripts/skalling-refresh.sh','--apply',self.project)
        self.assert_clean()
        # A real contribution can be committed without including Skalling.
        (self.project/'README.md').write_bytes(self.original['README.md']+b'Useful project documentation.\n')
        self.git('add','-A')
        self.git('-c','user.name=Test','-c','user.email=test@example.invalid','-c','commit.gpgsign=false','commit','-qm','Improve documentation')
        self.assertEqual(self.git('show','--format=','--name-only','HEAD').stdout.strip(),'README.md')
        # Force-adding a hidden artifact is rejected by the installed hook.
        self.git('add','-f','.opencode/agents/Alex.md')
        denied=self.git('-c','user.name=Test','-c','user.email=test@example.invalid','commit','-qm','Do not publish',check=False)
        self.assertNotEqual(denied.returncode,0)
        self.assertIn('Privacidad externa incompleta',denied.stderr)

    def test_external_dry_run_and_collisions_preserve_repository(self):
        self.script('setup.sh','--target',self.project,'--privacy','external','--dry-run')
        self.assert_clean()
        self.assertFalse((self.project/'.opencode').exists())
        self.assertNotEqual(self.git('config','--local','--get','skalling.privacyMode',check=False).returncode,0)
        own=self.project/'.opencode/opencode.json'; own.parent.mkdir(); own.write_text('{"own":true}\n')
        result=self.script('setup.sh','--target',self.project,'--privacy','external',check=False)
        self.assertNotEqual(result.returncode,0)
        self.assertIn('configuración ajena',result.stderr)
        self.assertEqual(own.read_text(),'{"own":true}\n')
        self.assertFalse((self.project/'.opencode/context/team.db').exists())

    def test_choose_external_before_init_and_detect_broken_exclusions(self):
        self.script('scripts/skalling-privacy.sh','external',self.project)
        self.assert_clean()
        self.assertFalse((self.project/'.opencode').exists())
        self.script('scripts/skalling-privacy.sh','external',self.project)
        exclude=self.project/'.git/info/exclude'
        self.assertEqual(exclude.read_text().count('# --- Skalling:'),1)
        exclude.write_text('')
        result=self.script('scripts/skalling-privacy.sh','status',self.project,check=False)
        self.assertEqual(result.returncode,3)

    def test_migration_cleans_only_owned_blocks_with_backup(self):
        self.script('setup.sh','--target',self.project)
        self.assertNotEqual((self.project/'.gitignore').read_bytes(),self.original['.gitignore'])
        self.script('scripts/skalling-privacy.sh','external',self.project)
        self.assert_clean()
        self.assertTrue(list((self.project/'.git').glob('skalling-privacy-backup-*')))
        # Inherited external mode survives a direct reinstall without flags.
        self.script('setup.sh','--target',self.project)
        self.assert_clean()

    def test_gate_blocks_backups_root_markers_and_push_even_without_database(self):
        self.script('scripts/skalling-privacy.sh','external',self.project)
        for name, data in [('.skalling-backups/leak.txt','private'),
                           ('.gitignore','# --- Skalling: artefactos locales (gestionado por setup.sh, no editar a mano) ---\n')]:
            path=self.project/name; path.parent.mkdir(parents=True,exist_ok=True); path.write_text(data)
            self.git('add','-f',name)
            result=subprocess.run(['python3',str(ROOT/'scripts/hooks/git-gate.py'),'pre-commit'],cwd=self.project,env=self.env,capture_output=True,text=True)
            self.assertNotEqual(result.returncode,0)
            self.assertIn('Privacidad externa incompleta',result.stderr)
            self.git('reset','-q','HEAD','--',name)
        # Construct a forbidden commit by explicitly bypassing hooks only in this fixture.
        self.git('add','-f','.skalling-backups/leak.txt')
        self.git('-c','core.hooksPath=/dev/null','-c','user.name=Test','-c','user.email=test@example.invalid','commit','-qm','Forbidden fixture')
        commit=self.git('rev-parse','HEAD').stdout.strip()
        remote=self.git('rev-parse','HEAD^').stdout.strip()
        result=subprocess.run(['python3',str(ROOT/'scripts/hooks/git-gate.py'),'pre-push'],cwd=self.project,env=self.env,
                              input=f'refs/heads/main {commit} refs/heads/main {remote}\n',capture_output=True,text=True)
        self.assertNotEqual(result.returncode,0)
        self.assertIn('Privacidad externa incompleta',result.stderr)

    def test_external_rejects_shared_ci_and_custom_hook_paths(self):
        result=self.script('setup.sh','--target',self.project,'--privacy','external','--with-ci',check=False)
        self.assertNotEqual(result.returncode,0)
        self.assertFalse((self.project/'.github').exists())
        self.git('config','core.hooksPath','.githooks')
        result=self.script('setup.sh','--target',self.project,'--privacy','external',check=False)
        self.assertNotEqual(result.returncode,0)
        self.assertIn('core.hooksPath',result.stderr)
        self.assertFalse((self.project/'.opencode').exists())

    def test_linked_worktree_uses_shared_local_privacy_and_exclusions(self):
        self.script('scripts/skalling-privacy.sh','external',self.project)
        worktree=self.base/'worktree'
        self.git('worktree','add','--detach',str(worktree),'HEAD')
        status=self.script('scripts/skalling-privacy.sh','status',worktree)
        self.assertIn('external',status.stdout)
        artifact=worktree/'.opencode/agents/Alex.md'
        artifact.parent.mkdir(parents=True); artifact.write_text('private')
        subprocess.run(['git','-C',str(worktree),'add','-A'],env=self.env,check=True)
        staged=subprocess.check_output(['git','-C',str(worktree),'diff','--cached','--name-only'],env=self.env)
        self.assertEqual(staged,b'')


if __name__=='__main__':
    unittest.main()
