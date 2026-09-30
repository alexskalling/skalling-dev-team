#!/usr/bin/env python3
"""Typed, atomic memory writes. Batch takes a JSON array of positional operations.

Example: batch '[["concept","slug","Title","Body"],["preference","slug","Body"]]'
The public shell wrapper exports one canonical dump after the whole transaction.
"""
import json
import os
import sys
from teamdb_guard import connect

SCHEMAS = {
    'concept': ('concepts', ('slug', 'title', 'body_md', 'category'), ('general',), 'updated_at'),
    'decision': ('decisions', ('slug', 'title', 'body_md', 'status'), ('accepted',), 'decided_at'),
    'preference': ('preferences', ('slug', 'body_md', 'scope'), ('project',), None),
    'problem': ('known_problems', ('slug', 'title', 'symptom_md', 'workaround_md', 'status'), ('', 'open'), None),
}


def write(db, operations):
    if not isinstance(operations, list) or not 1 <= len(operations) <= 100:
        raise ValueError('batch requiere 1..100 operaciones')
    prepared = []
    for op in operations:
        if not isinstance(op, list) or not op or not all(isinstance(x, str) for x in op) or op[0] not in SCHEMAS:
            raise ValueError('operación inválida: [tipo, slug, campos...]')
        table, columns, defaults, timestamp = SCHEMAS[op[0]]
        values = op[1:]
        required = len(columns) - len(defaults)
        if not required <= len(values) <= len(columns) or not all(v.strip() for v in values[:required]):
            raise ValueError('campos requeridos faltantes o vacíos')
        values += list(defaults[len(values) - required:])
        if table == 'decisions':
            columns += ('decided_by',)
            values.append(os.environ.get('TEAMDB_ACTOR') or 'pau')
        elif table == 'preferences':
            columns += ('source',)
            values.append(os.environ.get('TEAMDB_ACTOR') or 'pau')
        prepared.append((table, columns, values, timestamp))
    conn = connect(db, timeout=5)
    changed = 0
    try:
        conn.execute('BEGIN IMMEDIATE')
        for table, columns, values, timestamp in prepared:
            previous = conn.execute(f"SELECT {','.join(columns)} FROM {table} WHERE slug=?", (values[0],)).fetchone()
            if previous and tuple(previous) == tuple(values):
                continue  # Do not grow history or alter timestamps for identical memory.
            updates = ','.join(f'{c}=excluded.{c}' for c in columns[1:])
            if timestamp:
                updates += f",{timestamp}=datetime('now')"
            insert_columns = ','.join(columns)
            placeholders = ','.join('?' for _ in values)
            created = timestamp or ('discovered_at' if table == 'known_problems' else None)
            if created:
                insert_columns += ',' + created
                placeholders += ",datetime('now')"
            conn.execute(f"INSERT INTO {table}({insert_columns}) VALUES({placeholders}) "
                         f"ON CONFLICT(slug) DO UPDATE SET {updates}", values)
            changed += 1
        conn.commit()
    except Exception:
        conn.rollback()
        raise
    finally:
        conn.close()
    return changed


if __name__ == '__main__':
    try:
        db, kind, *fields = sys.argv[1:]
        operations = json.loads(fields[0]) if kind == 'batch' and len(fields) == 1 else [[kind, *fields]]
        print(json.dumps({'changes': write(db, operations)}))
    except Exception as error:
        print('ERROR: ' + str(error), file=sys.stderr)
        sys.exit(1)
