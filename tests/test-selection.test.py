import importlib.util
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
spec = importlib.util.spec_from_file_location('selection', ROOT / 'tests/run-selected.py')
selection = importlib.util.module_from_spec(spec)
spec.loader.exec_module(selection)


class Selection(unittest.TestCase):
    def test_known_plugin_includes_regressions_without_installers(self):
        plan = selection.select(['plugins/lib/git-guard.mjs'])
        self.assertFalse(plan['full'])
        self.assertIn('tests/permission-bypass.test.mjs', plan['tests'])
        self.assertNotIn('tests/setup.test.sh', plan['tests'])

    def test_unknown_shared_or_missing_scope_fails_closed_to_full(self):
        for paths in [[], ['sql/project-schema.sql'], ['scripts/lib/lib-teamdb.sh'],
                      ['new-runtime.py'], ['../outside'], ['tests/deleted.test.py']]:
            with self.subTest(paths=paths):
                self.assertTrue(selection.select(paths)['full'])

    def test_mixed_scope_is_union_and_has_no_duplicates(self):
        plan = selection.select(['plugins/lib/git-guard.mjs', 'plugins/lib/workflow.mjs',
                                 'tests/permission-bypass.test.mjs'])
        self.assertFalse(plan['full'])
        self.assertEqual(len(plan['tests']), len(set(plan['tests'])))
        self.assertIn('tests/workflow-plugin.test.mjs', plan['tests'])

    def test_every_configured_test_exists(self):
        for tests in selection.IMPACT.values():
            for test in tests:
                self.assertTrue((ROOT / test).is_file(), test)

    def test_full_runners_have_no_duplicate_test_entries(self):
        import re
        a = (ROOT / 'tests/run-all.sh').read_text().split('COMMANDS=(', 1)[1].split('\n)', 1)[0]
        b = (ROOT / 'tests/teamdb-hardening-suite.sh').read_text().split('TESTS=(', 1)[1].split('\n)', 1)[0]
        names = re.findall(r'tests/[\w.-]+\.test\.(?:py|sh|mjs)', a + b)
        self.assertEqual(len(names), len(set(names)))


if __name__ == '__main__':
    unittest.main()
