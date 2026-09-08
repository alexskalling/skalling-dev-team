"""Exercise the distributed package, not just source prompt assertions."""
import json
import os
import sqlite3
import subprocess
import tempfile
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]


class InstalledWorkflow(unittest.TestCase):
    def test_install_bootstrap_refresh_and_plan(self):
        with tempfile.TemporaryDirectory(prefix='skalling-workflow-') as temporary:
            base = Path(temporary)
            config, project, binaries = (base / name for name in ('config', 'project', 'bin'))
            (project / 'app').mkdir(parents=True)
            binaries.mkdir()
            stub = binaries / 'gentle-ai'
            stub.write_text('#!/bin/sh\nwhile [ "$#" -gt 0 ]; do\n'
                            'if [ "$1" = --cwd ]; then mkdir -p "$2/.codegraph"; exit 0; fi\nshift\ndone\n')
            stub.chmod(0o755)
            env = dict(os.environ, SKALLING_OPENCODE_DIR=str(config),
                       SKALLING_DB_GLOBAL=str(config / 'team.db'), PATH=f'{binaries}:{os.environ["PATH"]}')

            def run(script, *args, input=None, check=True):
                result = subprocess.run(['bash', str(script), *map(str, args)], env=env,
                                        cwd=project, input=input, capture_output=True, text=True)
                if check:
                    self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
                return result

            package = project / 'package.json'
            package.write_text(json.dumps({'name': 'fixture', 'description': 'Portal inicial',
                                          'dependencies': {'next': '15.0.0', 'react': '19.0.0'}}))
            (project / 'app/globals.css').write_text(':root { --brand: red; }')
            run(ROOT / 'install-global.sh', '--force')
            self.assertTrue((config / '.skalling-backups/install.log').exists())
            self.assertEqual((config / 'skills/writing-plans/SKILL.md').read_text(),
                             (ROOT / 'skills-base/writing-plans/SKILL.md').read_text())
            run(config / 'bootstrap-context.sh', '--target', project, '--force')
            context = project / '.opencode/context'
            self.assertFalse((context / 'proyecto').exists())
            self.assertFalse((context / 'stack').exists())

            def summary():
                with sqlite3.connect(context / 'team.db') as db:
                    return db.execute("SELECT body_md FROM concepts WHERE slug='project-summary'").fetchone()[0]

            self.assertIn('Portal inicial', summary())
            package.write_text(package.read_text().replace('Portal inicial', 'Portal actualizado'))
            run(config / 'bootstrap-context.sh', '--target', project, '--force')
            self.assertIn('Portal actualizado', summary())
            with sqlite3.connect(context / 'team.db') as db:
                db.execute("UPDATE concepts SET body_md='Decisión humana conservada' WHERE slug='project-summary'")
            run(config / 'bootstrap-context.sh', '--target', project, '--force')
            self.assertEqual(summary(), 'Decisión humana conservada')
            with sqlite3.connect(context / 'team.db') as db:
                pending = db.execute("SELECT value FROM schema_meta WHERE key='bootstrap.pending.project-summary'").fetchone()
                self.assertIn('Portal actualizado', pending[0])

            scripts = config / 'scripts'
            route = scripts / 'skalling-route.sh'
            common = ['classify', '--project', project, '--risk', 'low', '--scope', 'local']
            self.assertNotEqual(run(route, *common, check=False).returncode, 0)
            for kind in ('research', 'audit'):
                self.assertFalse(json.loads(run(route, *common, '--kind', kind).stdout)['implementation_allowed'])
            evidence = ['--kind', 'code', '--file', 'app/globals.css', '--acceptance',
                        'Ambos botones usan el color existente', '--reuse', 'Usar variable brand existente', '--visual']
            self.assertFalse(json.loads(run(route, *common, *evidence).stdout)['implementation_allowed'])
            capsule = json.loads(run(scripts / 'teamdb-context.sh', 'for-request', 'unificar estilos', '--visual', project).stdout)
            self.assertTrue(any(c['slug'] == 'design-system' for c in capsule['concepts']))
            run(scripts / 'teamdb-plan.sh', project, 'unify', 'Unificar estilos', '-', '--by=sol',
                '--purpose=Reutilizar estilos existentes', '--acceptance=Ambos botones comparten brand',
                '--strict-contract', input='- [ ] Unificar botones\n')
            run(scripts / 'teamdb-amend.sh', 'unify', '--add-task=Verificar botones',
                '--purpose=Evitar regresiones visuales', '--acceptance=Comparación visual correcta', '--by=sol', project)
            run(scripts / 'teamdb-amend.sh', 'unify', '--show', project)
            self.assertNotEqual(run(scripts / 'teamdb-execute-plan.sh', 'unify', project, check=False).returncode, 0)
            with sqlite3.connect(context / 'team.db') as db:
                plan_id = db.execute("SELECT id FROM plans WHERE slug='unify'").fetchone()[0]
            run(scripts / 'teamdb-plan-approve.sh', project, plan_id,
                'Reutilizar variable brand sin crear archivos CSS', 'Ambos botones comparten brand',
                'Aprobación sintética del fixture, no del usuario real')
            self.assertTrue(json.loads(run(route, *common, *evidence, '--plan-id', plan_id).stdout)['implementation_allowed'])
            pending_decision = json.loads(run(route, *common, *evidence, '--plan-id', plan_id,
                                             '--decision', 'pending').stdout)
            self.assertFalse(pending_decision['implementation_allowed'])
            self.assertTrue(pending_decision['needs_user_decision'])
            execution = json.loads(run(scripts / 'teamdb-execute-plan.sh', 'unify', project).stdout)
            self.assertTrue(execution['next_task'])
            self.assertFalse(list(context.glob('**/*.md')))


if __name__ == '__main__':
    unittest.main()
