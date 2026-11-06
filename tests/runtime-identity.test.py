"""Installed bytes and unchanged version numbers are not proof of current source."""
import importlib.util
import json
from pathlib import Path
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[1]
spec = importlib.util.spec_from_file_location('runtime', ROOT / 'scripts/skalling-runtime.py')
runtime = importlib.util.module_from_spec(spec)
spec.loader.exec_module(runtime)


class RuntimeIdentity(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory()
        self.addCleanup(self.tmp.cleanup)
        self.root = Path(self.tmp.name) / 'source'
        self.target = Path(self.tmp.name) / 'installed'
        (self.root / 'agents-base').mkdir(parents=True)
        (self.root / 'agents-base/Alex.md').write_text('original policy')
        (self.root / 'VERSION').write_text('1.0.0')
        for name in runtime.REQUIRED:
            path = self.target / name
            path.parent.mkdir(parents=True, exist_ok=True)
            path.write_text('fixture')
        (self.target / 'VERSION').write_text('1.0.0')
        self.manifest = {'version': '1.0.0', 'files': runtime.files(self.target),
                         'source_fingerprint': runtime.source_fingerprint(self.root)}
        (self.target / 'runtime-manifest.json').write_text(json.dumps(self.manifest))

    def test_same_version_cannot_hide_a_changed_source_policy(self):
        self.assertTrue(runtime.check(self.root, self.target)['ready'])
        (self.root / 'agents-base/Alex.md').write_text('new policy')
        result = runtime.check(self.root, self.target)
        self.assertFalse(result['ready'])
        self.assertFalse(result['source_matches'])
        self.assertEqual(result['expected'], result['installed'])

    def test_legacy_manifest_reports_unknown_source_instead_of_ready(self):
        del self.manifest['source_fingerprint']
        (self.target / 'runtime-manifest.json').write_text(json.dumps(self.manifest))
        self.assertFalse(runtime.check(self.root, self.target)['ready'])

    def test_installed_reference_preserves_identity_but_rejects_modified_runtime(self):
        self.assertTrue(runtime.check(self.target, self.target)['ready'])
        (self.target / 'scripts/skalling-workflow.py').write_text('modified')
        result = runtime.check(self.target, self.target)
        self.assertFalse(result['ready'])
        self.assertIsNone(result['expected_source'])

    def test_memory_and_tests_do_not_change_the_runtime_identity(self):
        before = runtime.source_fingerprint(self.root)
        (self.root / '.opencode/context').mkdir(parents=True)
        (self.root / '.opencode/context/team.db').write_bytes(b'private memory')
        (self.root / 'tests').mkdir()
        (self.root / 'tests/fixture.py').write_text('changed test')
        self.assertEqual(runtime.source_fingerprint(self.root), before)


if __name__ == '__main__':
    unittest.main()
