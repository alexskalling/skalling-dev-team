import subprocess
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]


class Generation(unittest.TestCase):
    def test_distributed_permissions_are_generated_from_policy(self):
        result = subprocess.run(['python3', str(ROOT / 'scripts/permission-policy.py'), '--check'],
                                cwd=ROOT, capture_output=True, text=True)
        self.assertEqual(result.returncode, 0, result.stderr)

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
