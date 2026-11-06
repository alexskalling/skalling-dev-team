"""Adding a reference must not turn a managed skill into a customization."""
import json
from pathlib import Path
import sys
import tempfile
import unittest

sys.path.insert(0, str(Path(__file__).resolve().parents[1] / 'scripts'))
from skalling_skills import repair, digest


class SkillUpgrade(unittest.TestCase):
    def test_new_reference_updates_managed_skill_and_preserves_real_customization(self):
        with tempfile.TemporaryDirectory() as tmp:
            root, target = Path(tmp)/'source', Path(tmp)/'installed'
            (root/'data').mkdir(parents=True)
            (root/'data/skills-by-stack.yaml').write_text('core:\n  - name: sample\n')
            skill = root/'skills-base/sample'
            skill.mkdir(parents=True)
            body = '---\nname: sample\ndescription: "Original rule"\n---\nOld instructions\n'
            (skill/'SKILL.md').write_text(body)
            self.assertEqual(repair(root, target), [])
            (skill/'references').mkdir()
            (skill/'references/guide.md').write_text('Detailed examples')
            (skill/'SKILL.md').write_text(body.replace('Old instructions', 'New instructions'))
            self.assertEqual(repair(root, target), [])
            installed = target/'skills/sample'
            self.assertEqual(digest(skill), digest(installed))
            self.assertEqual(repair(root, target), [])
            (installed/'SKILL.md').write_text(body + 'User customization\n')
            (installed/'references/guide.md').unlink()
            self.assertEqual(repair(root, target), ['sample'])
            self.assertIn('User customization', (installed/'SKILL.md').read_text())
            self.assertTrue((installed/'references/guide.md').is_file())
            self.assertEqual(repair(root, target), ['sample'])
            self.assertNotEqual(json.loads((target/'skills/.skalling-managed.json').read_text())['sample'], digest(installed))


if __name__ == '__main__':
    unittest.main()
