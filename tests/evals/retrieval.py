"""Small reproducible retrieval comparison. No model calls or semantic-quality claim."""
import json
from pathlib import Path
import sqlite3
import sys
import time
from contextlib import closing

ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(ROOT / 'scripts'))
from skalling_context import request_context

CASES = [
    ('autenticacion', 'access', 'La autenticación usa el proveedor existente.'),
    ('sesion', 'cookies', 'La sesión expira después de treinta minutos.'),
    ('transaccion', 'payments', 'La transacción fallida revierte ambos saldos.'),
    ('sqlite', 'storage', 'Usamos SQLite para la persistencia local.'),
    ('rollback', 'recovery', 'El rollback debe preservar los datos previos.'),
    ('configuracion', 'settings', 'La configuración admite cero como valor válido.'),
]


def evaluate():
    with closing(sqlite3.connect(':memory:')) as db:
        db.executescript((ROOT / 'sql/project-schema.sql').read_text())
        for _, slug, body in CASES:
            db.execute('INSERT INTO decisions(slug,title,body_md,status) VALUES(?,?,?,?)',
                       (slug, slug, body, 'accepted'))
        db.execute("INSERT INTO decisions(slug,title,body_md,status) VALUES('obsolete','sqlite','Usar otra base','superseded')")
        result = {}
        for mode in ('lexical', 'fts'):
            hits = 0
            start = time.perf_counter()
            for query, expected, _ in CASES:
                capsule = request_context(db, ROOT, query, top_k=3, query_only=True, search_mode=mode)
                found = {item['slug'] for item in capsule['decisions']}
                assert 'obsolete' not in found
                hits += expected in found
            result[mode] = {'queries':len(CASES), 'hits_at_3':hits,
                            'duration_ms':round((time.perf_counter()-start)*1000,3)}
        return result


if __name__ == '__main__':
    print(json.dumps({'kind':'retrieval-fixture', 'results':evaluate(),
                      'limits':'Six lexical/accent cases; no model, synonym or production latency evaluation.'}, indent=2))
