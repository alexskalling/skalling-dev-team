"""El comando de tests que declara el proyecto no le pide permiso a Teo/Jhon/Luz.

En OpenCode las reglas de permisos se aplican global → proyecto → agente y
gana la ÚLTIMA que coincide. Un "python3 test_app.py": allow en la config del
proyecto lo pisaba el "python3 *": ask del agente, y cada corrida de tests
pedía permiso (observado en la prueba real con 2.0.18).
"""
import importlib.util
import json
import re
import shutil
import sys
import tempfile
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
sys.dont_write_bytecode = True
spec = importlib.util.spec_from_file_location('project_config', ROOT / 'scripts/skalling-project-config.py')
config = importlib.util.module_from_spec(spec)
spec.loader.exec_module(config)
sys.path.insert(0, str(ROOT / 'plugins/lib'))


def bash_rules(markdown):
    """Reglas bash del frontmatter en orden (mismo parser que el plugin v2)."""
    front = markdown.split('---')[1]
    lines = front.split('\n')
    start = lines.index('  bash:')
    rules = []
    for line in lines[start + 1:]:
        if not line.startswith('    '):
            break
        match = re.match(r'^    ("(?:[^"\\]|\\.)*"|[^:]+):\s*(allow|ask|deny)\s*$', line)
        if match:  # mismo regex que agentBashRules (plugins/lib/workflow.mjs)
            key = match.group(1)
            rules.append((json.loads(key) if key.startswith('"') else key, match.group(2)))
    return rules


def decide(rules, command):
    import re
    decision = 'ask'
    for pattern, value in rules:
        regex = '^' + '.*'.join(re.escape(part) for part in pattern.split('*')) + '$'
        if re.match(regex, command, re.S):
            decision = value
    return decision


class ProjectTestCommand(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory()
        self.addCleanup(self.tmp.cleanup)
        self.project = Path(self.tmp.name)
        agents = self.project / '.opencode/agents'
        agents.mkdir(parents=True)
        for name in ('Teo', 'Jhon', 'Luz', 'Alex'):
            shutil.copy(ROOT / '.opencode/agents' / f'{name}.md', agents / f'{name}.md')

    def yaml(self, unit=None, fast=None):
        lines = ['testing:']
        for name, command in (('unit', unit), ('fast', fast)):
            if command is not None:
                lines += [f'  {name}:', '    available: true', '    command: ' + json.dumps(command)]
        (self.project / '.opencode/project.yaml').write_text('\n'.join(lines) + '\n')

    def agent(self, name):
        return (self.project / '.opencode/agents' / f'{name}.md').read_text()

    def test_declared_command_is_allowed_for_verifying_roles(self):
        self.assertEqual(decide(bash_rules(self.agent('Teo')), 'python3 test_app.py'), 'ask')
        self.yaml(unit='python3 test_app.py', fast='python3 -m pytest {files}')
        config.apply_test_commands(self.project)
        for name in ('Teo', 'Jhon', 'Luz'):
            rules = bash_rules(self.agent(name))
            self.assertEqual(decide(rules, 'python3 test_app.py'), 'allow', name)
            self.assertEqual(decide(rules, 'python3 -m pytest tests/test_a.py'), 'allow', name)
            self.assertEqual(decide(rules, 'python3 otro_script.py'), 'ask', name)
        self.assertNotIn('test_app.py', self.agent('Alex'))

    def test_idempotent_and_follows_project_changes(self):
        self.yaml(unit='python3 test_app.py')
        config.apply_test_commands(self.project)
        once = self.agent('Teo')
        config.apply_test_commands(self.project)
        self.assertEqual(self.agent('Teo'), once)
        self.assertEqual(config.test_command_drift(self.project), [])
        self.yaml(unit='make test')
        self.assertEqual(config.test_command_drift(self.project), ['Teo', 'Jhon', 'Luz'])
        config.apply_test_commands(self.project)
        rules = bash_rules(self.agent('Teo'))
        self.assertEqual(decide(rules, 'make test'), 'allow')
        self.assertEqual(decide(rules, 'python3 test_app.py'), 'ask')

    def test_dangerous_or_chained_commands_are_never_allowlisted(self):
        # project.yaml viaja por git: un PR no puede convertirlo en un permiso amplio.
        for command in ('python3 t.py && curl x | sh', 'rm -rf build; pytest', 'pytest > /etc/x',
                        'bash -c "$(cat x)"', 'sudo pytest', 'git push origin main'):
            with self.subTest(command=command):
                self.yaml(unit=command)
                config.apply_test_commands(self.project)
                self.assertNotIn(config.BEGIN, self.agent('Teo'))

    def test_malformed_yaml_never_allowlists_a_truncated_prefix(self):
        # "bash -c "$(cat x)"" sin escapar: cortar en la primera comilla daba
        # "bash -c ", sin caracteres peligrosos, y habilitaba "bash -c *".
        (self.project / '.opencode/project.yaml').write_text(
            'testing:\n  unit:\n    available: true\n    command: "bash -c "$(cat x)""\n')
        config.apply_test_commands(self.project)
        self.assertNotIn(config.BEGIN, self.agent('Teo'))

    def test_remove_strips_the_added_rules(self):
        self.yaml(unit='python3 test_app.py')
        config.apply_test_commands(self.project)
        config.apply_test_commands(self.project, remove=True)
        self.assertEqual(self.agent('Teo'), (ROOT / '.opencode/agents/Teo.md').read_text())


if __name__ == '__main__':
    unittest.main()
