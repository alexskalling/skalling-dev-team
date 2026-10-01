"""Alex coexists with the native primary agents without forcing their Git flow."""
import importlib.util
import json
import os
from pathlib import Path
import subprocess
import tempfile
import unittest

ROOT=Path(__file__).resolve().parents[1]
spec=importlib.util.spec_from_file_location('project_config',ROOT/'scripts/skalling-project-config.py')
config=importlib.util.module_from_spec(spec);spec.loader.exec_module(config)

class NativeAgents(unittest.TestCase):
    def test_efficiency_plugin_registered_once_and_removed_without_other_plugins(self):
        with tempfile.TemporaryDirectory() as temp:
            root=Path(temp);path=root/'.opencode/opencode.json'
            plugin=path.parent/'plugins/skalling-execution-efficiency'
            plugin.mkdir(parents=True);(plugin/'index.js').write_text('export default {}')
            path.write_text(json.dumps({'plugins':['other-plugin']}))
            for args in ([],[],['--check']):
                result=subprocess.run(['python3',str(ROOT/'scripts/skalling-project-config.py'),str(root),*args],capture_output=True,text=True)
                self.assertEqual(result.returncode,0,result.stderr+result.stdout)
            self.assertEqual(json.loads(path.read_text())['plugins'],['other-plugin',str(plugin.resolve())])
            subprocess.run(['python3',str(ROOT/'scripts/skalling-project-config.py'),str(root),'--remove'],check=True,capture_output=True)
            self.assertEqual(json.loads(path.read_text())['plugins'],['other-plugin'])

    def test_selector_and_upgrade_preserve_models(self):
        old={'agent':{'build':{'disable':True,'model':'custom/model'},'plan':{'disable':True},'general':{'disable':True},'Teo':{'mode':'primary'}}}
        result=config.expected(old)
        self.assertEqual(result['default_agent'],'Alex')
        primary={name for name,agent in result['agent'].items() if agent.get('mode')=='primary' and not agent.get('disable')}
        self.assertEqual(primary,{'Alex','build','plan'})
        self.assertEqual(result['agent']['build']['model'],'custom/model')
        self.assertFalse(result['agent']['general']['disable'])
        for role in config.ALL_AGENTS[1:]:self.assertEqual(result['agent'][role]['mode'],'subagent')
        self.assertEqual(config.expected(result),result)
        self.assertTrue(old['agent']['build']['disable'])

    def test_v2_native_overrides_are_repaired_too(self):
        result=config.expected({'agents':{'build':{'disable':True},'plan':{'disable':True}}})
        for role in ('build','plan'):
            self.assertFalse(result['agents'][role]['disable'])
            self.assertEqual(result['agents'][role]['mode'],'primary')

    def test_remove_does_not_leave_empty_skalling_agents_in_selector(self):
        removed=config.removed(config.expected({}))
        self.assertNotIn('agent',removed)
        self.assertNotIn('default_agent',removed)

    def test_local_specialist_header_is_subagent_without_losing_model(self):
        with tempfile.TemporaryDirectory() as temp:
            text='---\nmode: primary\nmodel: custom/provider\n---\nExisting instructions\n'
            actual=config.patched_project_agent(text,[], 'Teo',Path(temp))
            self.assertIn('mode: subagent',actual)
            self.assertIn('model: custom/provider',actual)
            self.assertTrue(actual.endswith('Existing instructions\n'))

    def test_install_command_repairs_legacy_selector_and_is_idempotent(self):
        with tempfile.TemporaryDirectory() as temp:
            root=Path(temp);path=root/'.opencode/opencode.json';path.parent.mkdir()
            path.write_text(json.dumps({'agent':{'build':{'disable':True},'plan':{'disable':True}}}))
            for args in ([],['--check']):
                result=subprocess.run(['python3',str(ROOT/'scripts/skalling-project-config.py'),str(root),*args],capture_output=True,text=True)
                self.assertEqual(result.returncode,0,result.stderr+result.stdout)
            self.assertFalse(json.loads(path.read_text())['agent']['build']['disable'])

    def test_real_commit_without_teamdb_for_native_agent_but_not_teo(self):
        with tempfile.TemporaryDirectory() as temp:
            root=Path(temp)
            def git(*args,**kw):return subprocess.run(['git',*args],cwd=root,capture_output=True,text=True,**kw)
            git('init','-q',check=True);git('config','user.name','Fixture',check=True);git('config','user.email','fixture@example.invalid',check=True)
            (root/'app.py').write_text('value=1\n');git('add','app.py',check=True)
            hook=root/'.git/hooks/pre-commit'
            hook.write_text('#!/bin/sh\nexec python3 "'+str(ROOT/'scripts/hooks/git-gate.py')+'" pre-commit\n');hook.chmod(0o755)
            denied=git('commit','-m','fixture',env={**os.environ,'SKALLING_RUNTIME_AGENT':'teo'})
            self.assertNotEqual(denied.returncode,0)
            committed=git('commit','-m','fixture',env={**os.environ,'SKALLING_RUNTIME_AGENT':'build'})
            self.assertEqual(committed.returncode,0,committed.stderr)
            sha=git('rev-parse','HEAD',check=True).stdout.strip()
            payload=f'refs/heads/main {sha} refs/heads/main '+('0'*40)+'\n'
            pushed=subprocess.run(['python3',str(ROOT/'scripts/hooks/git-gate.py'),'pre-push'],cwd=root,input=payload,capture_output=True,text=True,env={**os.environ,'SKALLING_RUNTIME_AGENT':'build'})
            self.assertEqual(pushed.returncode,0,pushed.stderr)
            (root/'app.py').write_text('token="ghp_'+('a'*36)+'"\n');git('add','app.py',check=True)
            secret=git('commit','-m','fixture',env={**os.environ,'SKALLING_RUNTIME_AGENT':'build'})
            self.assertNotEqual(secret.returncode,0)
            self.assertIn('secreto',secret.stderr)

if __name__=='__main__':unittest.main()
