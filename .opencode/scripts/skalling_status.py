"""Read the current workflow store once; never infer live execution from a row."""
from contextlib import closing
import importlib.util
import json
from pathlib import Path
import sqlite3

TERMINAL = {'completed', 'superseded', 'abandoned'}


def workflows(db_path, identifier=None):
    with closing(sqlite3.connect(Path(db_path).resolve().as_uri() + '?mode=ro', uri=True)) as conn:
        if not conn.execute("SELECT 1 FROM sqlite_master WHERE name='agent_workflows'").fetchone():
            return []
        rows = conn.execute('SELECT id,body FROM agent_workflows' + (' WHERE id=?' if identifier else '')
                            + ' ORDER BY id', (identifier,) if identifier else ()).fetchall()
    result = []
    for key, body in rows:
        state = json.loads(body)
        if not isinstance(state, dict) or not isinstance(state.get('state'), str):
            raise ValueError(f'Workflow inválido: {key}; no se puede afirmar que no haya trabajo')
        state['id'] = key
        if identifier or state['state'] not in TERMINAL:
            result.append(state)
    return result


def describe(rows):
    # Reuse the engine's routing decisions instead of keeping another state map.
    spec = importlib.util.spec_from_file_location('skalling_workflow_status', Path(__file__).with_name('skalling-workflow.py'))
    engine = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(engine)
    for state in rows:
        state['next_step'] = engine.next_step(state)
        state['recommended_action'] = engine.next_action(state)
    return rows


def display(db_path, identifier=None):
    rows = describe(workflows(db_path, identifier))
    if not rows:
        return False
    print('━━━ Workflows de Skalling (estado persistido; no actividad en vivo)')
    for row in rows[:5]:
        print(f"- {row['id']} [{row['state']}]: {row.get('intent') or row.get('acceptance', '')}")
        for outcome in row.get('outcomes', []):
            print(f"  Resultado {outcome['id']}: {outcome['expected']}")
        print('  Siguiente: ' + row['next_step'] + '; id=' + row['id'])
    if len(rows) > 5:
        print(f'{len(rows) - 5} workflows adicionales; consultar por id.')
    if len(rows) > 1:
        print('Asociar el pedido a su id; no elegir por recencia.')
    return True
