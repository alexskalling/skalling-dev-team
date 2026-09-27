"""Lectura segura del dump versionado de TeamDB (db/teamdb/team.dump.sql).

El dump viaja por git: lo puede modificar cualquiera que abra un PR. Nunca se
entrega a sqlite3 como script (auditoría externa v0.12.0 #3: una línea
`.shell ...` ejecutaba comandos al restaurar). Acá solo se aceptan sentencias
`INSERT INTO "<tabla permitida>" (<columnas>) VALUES (<literales>);`; los
valores los evalúa SQLite con un autorizador que solo permite SELECT de
literales y funciones escalares, sobre una base en memoria.
"""
import re
import sqlite3

# Mismo orden que teamdb-dump.sh (padres antes que hijos; memory_versions
# después de las tablas que versiona, para que su valor restaurado prevalezca
# sobre el que ponen los triggers al insertar).
TABLES = ('concepts', 'decisions', 'preferences', 'known_problems', 'memory_versions', 'work_in_progress',
          'tags', 'memory_tags', 'memory_links', 'proposals', 'plans', 'specs', 'design_notes', 'tasks',
          'task_dependencies', 'task_claims', 'plan_history', 'task_context_capsules', 'skills_registry',
          'routing_decisions', 'receipts', 'task_lock_history', 'attempts', 'agent_workflows')

INSERT_RE = re.compile(r'^INSERT INTO "([^"]+)" \((.*?)\) VALUES \((.*)\);$', re.S)
IDENTIFIER_RE = re.compile(r'^[A-Za-z_][A-Za-z0-9_]*$')


def _literal_evaluator():
    db = sqlite3.connect(':memory:')
    db.text_factory = str
    allowed = {sqlite3.SQLITE_SELECT, sqlite3.SQLITE_FUNCTION}
    db.set_authorizer(lambda action, *_: sqlite3.SQLITE_OK if action in allowed else sqlite3.SQLITE_DENY)
    return db


def statements(path):
    """Sentencias completas: acepta dumps nuevos (una línea por fila) y viejos
    con strings multilínea. Comentarios `--` y líneas vacías se ignoran."""
    buf, number, start = '', 0, 0
    with open(path, encoding='utf-8') as handle:
        for line in handle:
            number += 1
            if not buf and (line.startswith('--') or not line.strip()):
                continue
            if not buf:
                start = number
            buf += line
            if sqlite3.complete_statement(buf):
                yield start, buf.strip()
                buf = ''
    if buf.strip():
        yield start, buf.strip()


def parse(path, allowed_tables=TABLES):
    """Devuelve (filas por tabla, problemas). Un problema es cualquier cosa que
    no sea un INSERT de datos en una tabla permitida: quien restaura aborta."""
    literal = _literal_evaluator()
    rows, problems = {}, []
    for line, statement in statements(path):
        match = INSERT_RE.match(statement)
        if not match:
            problems.append(f'línea {line}: no es un INSERT de datos: {statement[:80]!r}')
            continue
        table, column_part, value_part = match.groups()
        if table not in allowed_tables:
            problems.append(f'línea {line}: tabla no permitida: {table}')
            continue
        columns = [c.strip().strip('"') for c in column_part.split(',')]
        if not all(IDENTIFIER_RE.match(c) for c in columns):
            problems.append(f'línea {line}: columnas inválidas en {table}')
            continue
        try:
            values = literal.execute('SELECT ' + value_part).fetchone()
        except sqlite3.Error as error:
            problems.append(f'línea {line}: valores no literales en {table} ({error})')
            continue
        if values is None or len(values) != len(columns):
            problems.append(f'línea {line}: {len(columns)} columnas y otra cantidad de valores en {table}')
            continue
        rows.setdefault(table, []).append(dict(zip(columns, values)))
    literal.close()
    return rows, problems
