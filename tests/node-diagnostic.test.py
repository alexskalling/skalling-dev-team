"""Execute local diagnostics and prove side effects stay denied by Node permissions."""
from pathlib import Path
import os
import shutil
import subprocess
import sys
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[1]
RUNNER = ROOT / 'scripts/skalling-node-diagnostic.py'
NODE = shutil.which('node')

class Diagnostic(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory()
        self.addCleanup(self.tmp.cleanup)
        self.root = Path(self.tmp.name)
        probe = subprocess.run([NODE, '--permission', '-e', "if(process.permission.has('net')!==false)process.exit(1)"], capture_output=True)
        if probe.returncode:
            self.skipTest('Node with network permission restriction unavailable; capability must fail closed')

    def run_code(self, source, **kwargs):
        return subprocess.run(['python3', str(RUNNER), '--source', source], cwd=self.root,
                              capture_output=True, text=True, **kwargs)

    def test_read_project_and_execute_mocked_workflow(self):
        (self.root / 'workflow.js').write_text("const cp=require('node:child_process'); cp.execFileSync('gh',['pr','merge']);")
        result = self.run_code("const fs=require('fs'),vm=require('vm'),assert=require('assert'); const calls=[]; vm.runInNewContext(fs.readFileSync('workflow.js','utf8'),{require:()=>({execFileSync:(...args)=>calls.push(args)})}); assert.equal(calls[0][0],'gh'); console.log('MOCKED');")
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertIn('MOCKED', result.stdout)

    def test_write_child_network_worker_and_outside_reads_are_denied(self):
        outside = self.root.parent / (self.root.name + '-outside')
        outside.write_text('private')
        self.addCleanup(outside.unlink)
        import json
        codes = ["require('fs').writeFileSync('unexpected','x')",
                 "require('child_process').execFileSync('git',['push'])",
                 "require('http').get('http://127.0.0.1:9')",
                 "new (require('worker_threads').Worker)('0',{eval:true})",
                 "require('fs').readFileSync(" + json.dumps(str(outside)) + ")"]
        for code in codes:
            with self.subTest(code=code):
                result = self.run_code(code)
                self.assertNotEqual(result.returncode, 0)
                self.assertIn('ERR_ACCESS_DENIED', result.stderr)
        self.assertFalse((self.root / 'unexpected').exists())

    def test_env_cannot_inject_preload_or_expose_tokens(self):
        result = self.run_code("if(process.env.GH_TOKEN || process.env.NODE_OPTIONS)throw Error('leaked'); console.log('clean')",
                               env={**os.environ, 'GH_TOKEN':'fixture-secret', 'NODE_OPTIONS':'--require /missing/preload.cjs'})
        self.assertEqual(result.returncode, 0, result.stderr)

    def test_extra_flags_are_rejected(self):
        result = subprocess.run(['python3',str(RUNNER),'--source','0','--allow-child-process'],capture_output=True,text=True)
        self.assertNotEqual(result.returncode,0)
        self.assertIn('unrecognized arguments',result.stderr)

    def test_unsupported_runtime_never_runs_diagnostic(self):
        binary = self.root / 'node'
        binary.write_text('#!/bin/sh\nexit 1\n')
        binary.chmod(0o755)
        result = subprocess.run([sys.executable, str(RUNNER), '--source', 'throw Error("must not run")'],
                                cwd=self.root, env={**os.environ, 'PATH':str(self.root)},
                                capture_output=True, text=True)
        self.assertNotEqual(result.returncode, 0)
        self.assertIn('Diagnóstico no ejecutado', result.stderr)

if __name__ == '__main__': unittest.main()
