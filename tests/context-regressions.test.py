import json
import re
import sqlite3
import subprocess
import tempfile
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]


class ContextRegression(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory()
        self.addCleanup(self.tmp.cleanup)
        self.project = Path(self.tmp.name)
        context = self.project / '.opencode/context'
        context.mkdir(parents=True)
        self.db = context / 'team.db'
        with sqlite3.connect(self.db) as db:
            db.executescript((ROOT / 'sql/project-schema.sql').read_text())
            for slug, body in [('project-summary', 'Portal de operaciones'),
                               ('design-system', 'Estilos existentes. ' * 40 + 'NO cambiar la fuente corporativa.')]:
                db.execute("INSERT INTO concepts(slug,title,body_md,updated_at) VALUES(?,?,?,datetime('now'))", (slug, slug, body))

    def capsule(self, *args):
        return subprocess.run(['bash', str(ROOT / 'scripts/teamdb-context.sh'), 'for-request',
                               *args, str(self.project)], capture_output=True, text=True)

    def test_missing_query_is_an_error(self):
        self.assertNotEqual(self.capsule('--max-bytes=8000').returncode, 0)

    def test_visual_request_preserves_complete_design_rules(self):
        result = self.capsule('unificar estilos', '--visual')
        self.assertEqual(result.returncode, 0, result.stderr)
        data = json.loads(result.stdout)
        design = next(x for x in data['concepts'] if x['slug'] == 'design-system')
        self.assertTrue(design['body'].endswith('NO cambiar la fuente corporativa.'))

    def test_small_budget_reports_omissions_without_losing_everything(self):
        result = self.capsule('estilos', '--visual', '--max-bytes=700')
        self.assertEqual(result.returncode, 0, result.stderr)
        data = json.loads(result.stdout)
        self.assertLessEqual(len(result.stdout.strip().encode()), 700)
        self.assertTrue(data['needs_expansion'])
        self.assertTrue(any(x['slug'] == 'project-summary' for x in data['concepts']))
        self.assertTrue(any(x['slug'] == 'design-system' for x in data['omitted']))

    def test_initialized_db_does_not_authorize_a_blind_request(self):
        with sqlite3.connect(self.db) as db:
            db.execute("INSERT INTO schema_meta VALUES('project_readiness','initialized')")
        command = ['bash', str(ROOT / 'scripts/skalling-route.sh'), 'classify', '--kind', 'code', '--project',
                   str(self.project), '--risk', 'low', '--scope', 'local']
        result = subprocess.run(command, capture_output=True, text=True, check=True)
        self.assertFalse(json.loads(result.stdout)['implementation_allowed'])
        (self.project / 'app.ts').write_text('export const value = 1;')
        evidence = ['--file', 'app.ts', '--acceptance', 'Valor mantiene su contrato',
                    '--reuse', 'Modificar constante existente']
        result = subprocess.run(command + evidence, capture_output=True, text=True, check=True)
        self.assertTrue(json.loads(result.stdout)['implementation_allowed'])
        result = subprocess.run(command + evidence + ['--risk', 'high'], capture_output=True, text=True, check=True)
        self.assertFalse(json.loads(result.stdout)['implementation_allowed'])
        with sqlite3.connect(self.db) as db:
            db.execute("INSERT INTO plans(slug,title,design_md,status) VALUES('demo','Plan demo','Borrador','draft')")
            plan_id = db.execute("SELECT id FROM plans WHERE slug='demo'").fetchone()[0]
            db.execute("INSERT INTO tasks(plan_id,slug,title,purpose,acceptance_md,status) VALUES(?,'task-one','Cambio concreto','Preservar contrato','Valor esperado','pending')", (plan_id,))
        subprocess.run(['bash', str(ROOT / 'scripts/teamdb-plan-approve.sh'), str(self.project), str(plan_id),
                        'Modificar la constante actual sin crear abstracciones', 'El valor esperado se verifica',
                        'Pedido explícito del usuario: corregir el valor'], capture_output=True, text=True, check=True)
        result = subprocess.run(command + evidence + ['--risk', 'high', '--plan-id', str(plan_id)], capture_output=True, text=True, check=True)
        self.assertTrue(json.loads(result.stdout)['implementation_allowed'])

    def test_bootstrap_preserves_human_memory_and_does_not_invent_tests(self):
        (self.project / 'app').mkdir()
        (self.project / 'app/style.css').write_text(':root { --brand: red; }')
        (self.project / 'package.json').write_text(json.dumps({'name': 'demo', 'description': 'Portal real'}))
        yaml = self.project / '.opencode/project.yaml'
        yaml.write_text('stack:\n  language: typescript\n  framework: nextjs\n  package_manager: pnpm\n'
                        'frontend:\n  has_ui: true\n  design_system_required: false\nmodules:\n  - src/\n'
                        'testing:\n  unit:\n    available: true\n    command: "npm test"\n')
        subprocess.run(['python3', str(ROOT / 'scripts/skalling-bootstrap-context.py'),
                        '--project', str(self.project)], capture_output=True, check=True)
        self.assertFalse((self.project / '.opencode/context/proyecto').exists())
        self.assertNotIn('npm test', yaml.read_text())
        self.assertIn('available: false', yaml.read_text())
        with sqlite3.connect(self.db) as db:
            summary = db.execute("SELECT body_md FROM concepts WHERE slug='project-summary'").fetchone()[0]
            self.assertEqual(summary, 'Portal de operaciones')
            self.assertEqual(db.execute("SELECT value FROM schema_meta WHERE key='project_readiness'").fetchone()[0], 'initialized')

    def test_legacy_archive_keeps_exact_bytes_and_export_comes_from_db(self):
        legacy = self.project / '.opencode/context/proyecto'
        legacy.mkdir()
        content = b'Memoria humana importante\n'
        (legacy / 'custom.md').write_bytes(content)
        tool = ['python3', str(ROOT / 'scripts/skalling-memory-layout.py'), '--project', str(self.project)]
        result = subprocess.run(tool + ['--archive-legacy'], capture_output=True, text=True, check=True)
        backup = Path(json.loads(result.stdout)['backup'])
        self.assertEqual((backup / 'proyecto/custom.md').read_bytes(), content)
        self.assertFalse(legacy.exists())
        with sqlite3.connect(self.db) as db:
            self.assertEqual(db.execute('SELECT content FROM legacy_documents').fetchone()[0], content)
        result = subprocess.run(tool + ['--export-concept', 'design-system'], capture_output=True, text=True, check=True)
        self.assertIn('NO cambiar la fuente corporativa.', Path(result.stdout.strip()).read_text())

    def test_agent_json_examples_match_real_schema(self):
        import jsonschema
        schema = json.loads((ROOT / 'templates/handoff.schema.json').read_text())
        examples = schema['examples'][:]
        for name in ('Teo', 'Sol'):
            examples.extend(json.loads(x) for x in re.findall(r'```json\n(.*?)\n```', (ROOT / f'agents-base/{name}.md').read_text(), re.S))
        for example in examples:
            jsonschema.validate(example, schema)


if __name__ == '__main__':
    unittest.main()
