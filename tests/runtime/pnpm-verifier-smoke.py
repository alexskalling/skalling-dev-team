"""Opt-in: actual pnpm must not install dependencies during either verifier."""
import importlib.util
import json
import os
from pathlib import Path
import shutil
import subprocess
import tempfile

ROOT = Path(__file__).resolve().parents[2]
PNPM = shutil.which('pnpm')
assert PNPM, 'This opt-in test requires pnpm'
spec = importlib.util.spec_from_file_location('workflow', ROOT / 'scripts/skalling-workflow.py')
engine = importlib.util.module_from_spec(spec)
spec.loader.exec_module(engine)

with tempfile.TemporaryDirectory(prefix='skalling-pnpm-verifier-') as tmp:
    root = Path(tmp)
    (root / '.opencode').mkdir()
    (root / '.opencode/project.yaml').write_text(
        'testing:\n  unit:\n    available: true\n    command: "pnpm run test"\n')
    (root / 'pnpm-workspace.yaml').write_text('verifyDepsBeforeRun: install\n')
    # No node_modules or lockfile: with auto-install this package would force
    # registry access. The test script itself only needs built-in Node APIs.
    (root / 'package.json').write_text(json.dumps({'name': 'skalling-regression',
        'scripts': {'test': 'node -e "console.log(42)"'},
        'dependencies': {'nonexistent-skalling-fixture': '1.0.0'}}))
    original = {name: (root / name).read_bytes() for name in ('package.json', 'pnpm-workspace.yaml')}
    env = {**os.environ, 'PNPM_CONFIG_VERIFY_DEPS_BEFORE_RUN': 'install',
           'npm_config_verify_deps_before_run': 'install', 'npm_config_offline': 'true'}
    code, output = engine.run_bounded([PNPM, 'run', 'test'], root, env, 20)
    assert code == 0 and '42' in output, output
    result = subprocess.run(['bash', str(ROOT / 'scripts/skalling-verify.sh'), str(root)],
                            env=env, capture_output=True, text=True, timeout=20)
    assert result.returncode == 0 and '42' in result.stdout, result.stderr
    assert not (root / 'node_modules').exists()
    assert not (root / 'pnpm-lock.yaml').exists()
    assert all((root / name).read_bytes() == content for name, content in original.items())
print('PASS actual pnpm: both verifiers run tests without network, installs or manifest/lock changes')
