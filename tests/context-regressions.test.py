import json
import re
from contextlib import closing
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
        with closing(sqlite3.connect(self.db)) as db, db:
            db.executescript((ROOT / 'sql/project-schema.sql').read_text())
            for slug, body in [('project-summary', 'Portal de operaciones'),
                               ('design-system', 'Estilos existentes. ' * 40 + 'NO cambiar la fuente corporativa.')]:
                db.execute("INSERT INTO concepts(slug,title,body_md,updated_at) VALUES(?,?,?,datetime('now'))", (slug, slug, body))

    def capsule(self, *args):
        return subprocess.run(['bash', str(ROOT / 'scripts/teamdb-context.sh'), 'for-request',
                               *args, str(self.project)], capture_output=True, text=True)

    def test_file_anchor_recovers_a_constraint_without_query_word_overlap(self):
        with closing(sqlite3.connect(self.db)) as db, db:
            db.execute("INSERT INTO decisions(slug,title,body_md,status) VALUES('boundary','Límite','src/auth/token.py exige validar expiración','accepted')")
        result = self.capsule('arreglar comportamiento', '--file=src/auth/token.py')
        self.assertEqual(result.returncode, 0, result.stderr)
        data = json.loads(result.stdout)
        self.assertIn('boundary', [x['slug'] for x in data['decisions']])

    def test_exact_memory_revision_can_be_reused_but_changes_are_returned(self):
        first = json.loads(self.capsule('contexto').stdout)
        row = next(x for x in first['concepts'] if x['slug'] == 'project-summary')
        second = json.loads(self.capsule('contexto', '--seen=' + row['read_key']).stdout)
        reused = next(x for x in second['concepts'] if x['slug'] == 'project-summary')
        self.assertTrue(reused['already_read'])
        self.assertNotIn('body', reused)
        with sqlite3.connect(self.db) as db:
            db.execute("UPDATE concepts SET body_md='Changed project purpose' WHERE slug='project-summary'")
        third = json.loads(self.capsule('contexto', '--seen=' + row['read_key']).stdout)
        changed = next(x for x in third['concepts'] if x['slug'] == 'project-summary')
        self.assertEqual(changed['body'], 'Changed project purpose')
        self.assertNotEqual(changed['read_key'], row['read_key'])

    def test_refresh_detects_actual_modules_and_source_drift(self):
        for name in ('tests', 'docs', 'scripts', 'plugins', 'agents-base'):
            (self.project / name).mkdir()
        (self.project / 'scripts/run.py').write_text('pass')
        (self.project / 'README.md').write_text('# Product\nA real development harness.\n')
        yaml = self.project / '.opencode/project.yaml'
        yaml.write_text('stack:\n  language: \nmodules:\n  - tests/\ntesting:\nfrontend:\n  has_ui: false\n')
        subprocess.run(['python3', str(ROOT / 'scripts/skalling-bootstrap-context.py'),
                        '--project', str(self.project)], check=True, capture_output=True)
        self.assertIn('  - scripts/', yaml.read_text())
        self.assertIn('  - plugins/', yaml.read_text())
        self.assertIn('Python', yaml.read_text())
        current = json.loads(self.capsule('contexto').stdout)['freshness']
        self.assertEqual(current['status'], 'current')
        self.assertIn('project-summary', current['pending_review'])
        (self.project / 'README.md').write_text('# Changed purpose')
        self.assertEqual(json.loads(self.capsule('contexto').stdout)['freshness']['status'], 'stale')

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
        with closing(sqlite3.connect(self.db)) as db, db:
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
        with closing(sqlite3.connect(self.db)) as db, db:
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
        with closing(sqlite3.connect(self.db)) as db, db:
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
        with closing(sqlite3.connect(self.db)) as db, db:
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


    # ── Auditoría externa v0.12.0 #6: un solo contrato de selección ──

    def test_more_matches_than_top_k_always_asks_for_expansion(self):
        with closing(sqlite3.connect(self.db)) as db, db:
            for i in range(9):
                db.execute("INSERT INTO decisions(slug,title,body_md,status) VALUES(?,?,?,'accepted')",
                           (f'pagos-{i}', f'Pagos regla {i}', f'Restricción de pagos número {i}'))
        data = json.loads(self.capsule('regla de pagos', '--top-k=8').stdout)
        self.assertEqual(len(data['decisions']), 8)
        self.assertTrue(data['more_matches'])
        self.assertTrue(data['needs_expansion'], 'more_matches sin needs_expansion escondía la novena decisión')
        self.assertTrue(any(o['table'] == 'decisions' for o in data['omitted']))

    def for_task(self, *args):
        return subprocess.run(['bash', str(ROOT / 'scripts/teamdb-context.sh'), 'for-task', 'plan', 'task',
                               *args, str(self.project)], capture_output=True, text=True)

    def seed_task(self, description='Implementar'):
        with closing(sqlite3.connect(self.db)) as db, db:
            db.execute("INSERT INTO plans(slug,title,design_md,status) VALUES('plan','Plan','d','approved')")
            plan = db.execute("SELECT id FROM plans WHERE slug='plan'").fetchone()[0]
            db.execute("INSERT INTO tasks(plan_id,slug,title,description_md,acceptance_md,status) VALUES(?,?,?,?,?,'pending')",
                       (plan, 'task', 'Tarea', description, 'Aceptación'))
            task = db.execute("SELECT id FROM tasks WHERE slug='task'").fetchone()[0]
            body = 'Contexto largo. ' * 60 + 'RESTRICCIÓN: nunca guardar tokens en localStorage.'
            db.execute("INSERT INTO decisions(slug,title,body_md,status) VALUES('tokens','Tokens',?,'accepted')", (body,))
            dec = db.execute("SELECT id FROM decisions WHERE slug='tokens'").fetchone()[0]
            db.execute("INSERT INTO task_context_capsules(task_id,memory_table,memory_id,relevance,provenance) "
                       "VALUES(?,'decisions',?,1.0,'linked')", (task, dec))

    def test_for_task_never_truncates_a_memory_silently(self):
        self.seed_task()
        data = json.loads(self.for_task('--max-bytes=8000').stdout)
        body = data['decisions'][0]['body_md']
        self.assertTrue(body.endswith('nunca guardar tokens en localStorage.'), 'la restricción se cortaba a 500 caracteres')

    def test_for_task_budget_counts_the_whole_output(self):
        self.seed_task(description='Descripción extensa. ' * 60)
        result = self.for_task('--max-bytes=1900')
        self.assertLessEqual(len(result.stdout.strip().encode()), 1900)
        data = json.loads(result.stdout)
        self.assertEqual(data['decisions'], [])
        self.assertTrue(data['needs_expansion'])
        self.assertEqual(data['omitted'], [{'table': 'decisions', 'slug': 'tokens'}])
        # Sin lugar ni para la referencia: igual se avisa que hay que buscar.
        tight = json.loads(self.for_task('--max-bytes=1500').stdout)
        self.assertTrue(tight['needs_expansion'] and tight['more_matches'])


if __name__ == '__main__':
    unittest.main()
