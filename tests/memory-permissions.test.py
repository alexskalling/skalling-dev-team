import fnmatch
import json
import unittest
from pathlib import Path

import yaml

ROOT = Path(__file__).resolve().parents[1]


class MemoryPermissions(unittest.TestCase):
    def test_every_agent_has_baseline_read_and_scoped_database_access(self):
        for name in ('Alex', 'Jes', 'Pol', 'Sol', 'Teo', 'Jhon', 'Luz', 'Pau'):
            for folder in ('agents-base', '.opencode/agents'):
                policy = yaml.safe_load((ROOT / folder / (name + '.md')).read_text().split('---', 2)[1])['permission']
                self.assertEqual(policy['teamdb_destructive'], 'ask')
                rules = yaml.safe_load((ROOT / folder / (name + '.md')).read_text().split('---', 2)[1])['permission']['bash']
                def action(command):
                    return next((value for pattern, value in reversed(list(rules.items()))
                                 if fnmatch.fnmatchcase(command, pattern)), 'ask')
                for command in ('cat README.md', 'head -n 10 app.py', 'ls', 'git status', 'git diff --stat',
                                'git log -4', 'git show HEAD', 'git ls-files', 'echo listo',
                                'bash /Users/example/.config/opencode/scripts/teamdb-read.sh "SELECT 1"',
                                '~/.config/opencode/scripts/teamdb-read.sh "SELECT 1"',
                                'bash .opencode/scripts/teamdb-read.sh "SELECT 1"'):
                    self.assertEqual(action(command), 'allow', (name, command))
                for command in ('git push', 'git commit -m x', 'python3 arbitrary.py', 'bash arbitrary.sh',
                                'python3 .opencode/scripts/teamdb-destructive.py', 'cp source team.db', 'rm -rf data',
                                'find . -delete', 'find . -exec rm {} ;', 'cat .env', 'sqlite3 team.db DROP'):
                    self.assertNotEqual(action(command), 'allow', (name, command))
                if name in ('Teo', 'Jhon', 'Luz'):
                    self.assertEqual(action('npm run test'), 'allow')
                    self.assertEqual(action('node_modules/.bin/vitest run'), 'allow')
                    self.assertEqual(action('./node_modules/.bin/vitest run'), 'allow')
                helper = {'Alex': 'skalling-goal', 'Sol': 'teamdb-plan', 'Teo': 'teamdb-claim',
                          'Jhon': 'skalling-review', 'Luz': 'skalling-review', 'Pau': 'teamdb-memory'}.get(name)
                if helper:
                    self.assertEqual(action(f'bash /home/test/.config/opencode/scripts/{helper}.sh action'), 'allow')

    def test_pau_allows_memory_without_allowing_arbitrary_shell(self):
        for path in ('agents-base/Pau.md', '.opencode/agents/Pau.md'):
            frontmatter = yaml.safe_load((ROOT / path).read_text().split('---', 2)[1])
            rules = frontmatter['permission']['bash']

            def action(command):
                return next((value for pattern, value in reversed(list(rules.items()))
                             if fnmatch.fnmatchcase(command, pattern)), 'ask')

            for home in ('/Users/example', '/home/example', '~'):
                command = f'bash {home}/.config/opencode/scripts/teamdb-memory.sh --project /project decision slug title body'
                self.assertEqual(action(command), 'allow')
            for command in ('cat README.md', 'git status --short', 'head -n 10 README.md'):
                self.assertEqual(action(command), 'allow')
            for command in ('git push origin main', 'git commit -m message', 'bash unknown.sh',
                            'rm -rf /project'):
                self.assertEqual(action(command), 'ask')
            self.assertEqual(action('sqlite3 other.db "DROP TABLE concepts"'), 'deny')
            edits = frontmatter['permission']['edit']
            # Use a nested path for the legacy Markdown prohibition.
            matches = [value for pattern, value in edits.items()
                       if fnmatch.fnmatchcase('.opencode/context/proyecto/decision.md', pattern)]
            self.assertEqual(matches[-1], 'deny')

    def test_distributed_config_keeps_unknown_shell_behind_approval(self):
        config = json.loads((ROOT / 'templates/opencode.json').read_text())
        rules = config['permission']['bash']
        for command, expected in [('bash /home/test/.config/opencode/scripts/teamdb-memory.sh decision a b c', 'allow'),
                                  ('bash unknown.sh', 'ask'), ('git push origin main', 'ask')]:
            matches = [value for pattern, value in rules.items() if fnmatch.fnmatchcase(command, pattern)]
            self.assertEqual(matches[-1], expected)


if __name__ == '__main__':
    unittest.main()
