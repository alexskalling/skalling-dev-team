import json
import subprocess
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]


class Generation(unittest.TestCase):
    def test_distributed_permissions_are_generated_from_policy(self):
        result = subprocess.run(['python3', str(ROOT / 'scripts/permission-policy.py'), '--check'],
                                cwd=ROOT, capture_output=True, text=True)
        self.assertEqual(result.returncode, 0, result.stderr)

    def test_git_dash_c_and_cd_forms_of_sensitive_git_cant_bypass_ask(self):
        # "git push"/"git reset"/etc. literales ya eran "ask", pero "git -C
        # <dir> push" y "cd <dir> && git push" no matcheaban ningun patron
        # especifico y caian al wildcard "*": "allow" -- un agente parado en
        # un worktree (cd ahi, o "git -C <worktree>") podia pushear sin que
        # se le pida permiso. Bloqueante: son exactamente las dos formas mas
        # probables en el flujo de worktrees que el propio proyecto fomenta.
        policy = json.loads((ROOT / 'data/permission-policy.json').read_text())
        sensitive = ['commit', 'push', 'reset', 'clean', 'checkout', 'restore']
        for cmd in sensitive:
            for pattern in (f'git -C * {cmd}', f'git -C * {cmd} *',
                             f'cd * && git {cmd}', f'cd * && git {cmd} *'):
                self.assertEqual(policy['rules'].get(pattern), 'ask', pattern)
                for profile_name, profile in policy['profiles'].items():
                    self.assertIn(pattern, profile['bash_patterns'],
                                  f'{pattern} falta en bash_patterns de {profile_name}')

    def test_branch_and_worktree_deletion_require_ask(self):
        policy = json.loads((ROOT / 'data/permission-policy.json').read_text())
        for pattern in ('git branch -d*', 'git branch -D*',
                         'git worktree remove*', 'git worktree prune*'):
            self.assertEqual(policy['rules'].get(pattern), 'ask', pattern)
            for profile_name, profile in policy['profiles'].items():
                self.assertIn(pattern, profile['bash_patterns'],
                              f'{pattern} falta en bash_patterns de {profile_name}')

    def test_renderer_uses_policy_even_if_source_permission_is_modified(self):
        import tempfile
        with tempfile.TemporaryDirectory() as folder:
            path = Path(folder) / 'Teo.md'
            source = (ROOT / 'agents-base/Teo.md').read_text()
            path.write_text(source.replace('"git push": ask', '"git push": allow'))
            result = subprocess.run(['bash', str(ROOT / 'scripts/render-agent.sh'), str(path)],
                                    capture_output=True, text=True)
            self.assertEqual(result.returncode, 0, result.stderr)
            self.assertIn('"git push": ask', result.stdout)


if __name__ == '__main__':
    unittest.main()
