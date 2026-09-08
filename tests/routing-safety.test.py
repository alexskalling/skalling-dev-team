import json
import sqlite3
import subprocess
import tempfile
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]


class RoutingSafety(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.temp = tempfile.TemporaryDirectory()
        cls.project = Path(cls.temp.name)
        context = cls.project / '.opencode/context'
        context.mkdir(parents=True)
        conn = sqlite3.connect(context / 'team.db')
        conn.executescript((ROOT / 'sql/project-schema.sql').read_text(encoding='utf-8'))
        conn.execute("INSERT INTO schema_meta(key,value) VALUES('project_readiness','ready')")
        conn.commit()
        conn.close()

    @classmethod
    def tearDownClass(cls):
        cls.temp.cleanup()

    def classify(self, *args):
        result = subprocess.run(['bash', str(ROOT / 'scripts/skalling-route.sh'),
                                 'classify', '--kind', 'code', '--project', str(self.project), *args],
                                capture_output=True, text=True)
        self.assertEqual(result.returncode, 0, result.stderr)
        return json.loads(result.stdout)

    def test_unknown_scope_is_not_fast_track(self):
        self.assertEqual(self.classify('--risk', 'low')['route'], 'SDD')

    def test_proven_local_change_is_fast_track(self):
        self.assertEqual(self.classify('--risk', 'low', '--scope', 'local')['route'], 'FAST-TRACK')

    def test_cross_cutting_change_escalates_even_if_labelled_low(self):
        self.assertEqual(self.classify('--risk', 'low', '--scope', 'cross-cutting')['risk'], 'high')

    def test_security_change_escalates_even_if_one_file(self):
        self.assertEqual(self.classify('--risk', 'low', '--scope', 'local', '--sensitive')['route'], 'SDD')

    def test_visual_change_requires_planning_even_if_local(self):
        data = self.classify('--risk', 'low', '--scope', 'local', '--visual')
        self.assertEqual(data['route'], 'INLINE')
        self.assertEqual(data['risk'], 'medium')

    def test_pending_human_decision_blocks_implementation(self):
        data = self.classify('--risk', 'low', '--scope', 'local', '--decision', 'pending')
        self.assertTrue(data['needs_user_decision'])
        self.assertFalse(data['implementation_allowed'])

    def test_research_does_not_authorize_writes(self):
        data = self.classify('--risk', 'high', '--kind', 'research')
        self.assertEqual(data['route'], 'RESEARCH')
        self.assertFalse(data['implementation_allowed'])

    def test_invalid_clarity_is_rejected(self):
        result = subprocess.run(['bash', str(ROOT / 'scripts/skalling-route.sh'),
                                 'classify', '--risk', 'low', '--clarity', 'typo'],
                                capture_output=True)
        self.assertNotEqual(result.returncode, 0)


if __name__ == '__main__':
    unittest.main()
