"""Bounded report of measured work; unknown time is never called zero or overhead."""
from contextlib import closing
import json
from pathlib import Path
import sqlite3
import sys

with closing(sqlite3.connect(Path(sys.argv[1]).resolve().as_uri()+'?mode=ro', uri=True)) as conn:
    conn.row_factory = sqlite3.Row
    rows = conn.execute('SELECT * FROM workflow_metrics ORDER BY started_at DESC LIMIT 20').fetchall()
    if not rows:
        print('Sin mediciones de funcionalidades todavía.')
    for row in rows:
        value = lambda key: row[key] if key in row.keys() and row[key] is not None else 'no medido'
        print(f"{row['request_id']}: route={value('route')} agents={value('agents_count')} risk={value('risk_level')} outcome={value('outcome')} duration_ms={value('duration_ms')} "
              f"handoffs={value('handoffs')} permissions={value('permission_prompts')} retries={value('retries')} "
              f"context_bytes={value('context_bytes')} tokens_in={value('tokens_input')} tokens_out={value('tokens_output')} cost={value('cost')}")
        workflow = conn.execute('SELECT body FROM agent_workflows WHERE id=?', (row['request_id'],)).fetchone()
        if workflow:
            state = json.loads(workflow[0])
            checks = [c for c in state.get('checks', []) if 'reused_from' not in c and c.get('duration_ms') is not None]
            print(f"  Comandos medidos: {len(checks)}; suma de duración={sum(c['duration_ms'] for c in checks)} ms (pueden solaparse).")
            for check in sorted(checks, key=lambda c: c['duration_ms'], reverse=True)[:3]:
                print(f"  Check: {check.get('argv', '?')} — {check['duration_ms']} ms; exit={check.get('exit_code', '?')}")
    print('Últimas 20 solicitudes. Esperas de usuario, proveedor y permisos: sin instrumentación temporal separada; no se infieren por resta.')
