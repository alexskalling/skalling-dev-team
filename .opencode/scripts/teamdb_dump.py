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

# Mismo orden que teamdb-dump.sh (padres antes que hijos). memory_versions se
# acepta solo por compatibilidad con dumps anteriores a la columna __version.
TABLES = ('concepts', 'decisions', 'preferences', 'known_problems', 'memory_versions', 'work_in_progress',
          'tags', 'memory_tags', 'memory_links', 'proposals', 'plans', 'specs', 'design_notes', 'tasks',
          'task_dependencies', 'task_claims', 'plan_history', 'task_context_capsules', 'skills_registry',
          'routing_decisions', 'receipts', 'task_lock_history', 'attempts', 'agent_workflows')

INSERT_RE = re.compile(r'^INSERT INTO "([^"]+)" \((.*?)\) VALUES \((.*)\);$', re.S)
IDENTIFIER_RE = re.compile(r'^[A-Za-z_][A-Za-z0-9_]*$')
# Columna sintética: versión de decisions/preferences/known_problems, que
# viaja con su fila. Quien aplica el dump la saca antes de insertar.
VERSION_COLUMN = '__version'
VERSIONED = ('decisions', 'preferences', 'known_problems')


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


# Clave natural por tabla para colapsar filas repetidas del dump (merge=union de
# git deja una fila por rama). Sin clave natural se usa la PK.
NATURAL_KEYS = {'tasks': ('plan_id', 'slug'), 'specs': ('plan_id', 'slug'), 'design_notes': ('plan_id', 'slug'),
                'tags': ('name',), 'skills_registry': ('name',)}


def _version(row):
    return str(row.get(VERSION_COLUMN) or row.get('updated_at') or '')


def natural_key(table, columns, pk):
    if table in NATURAL_KEYS:
        return NATURAL_KEYS[table]
    if 'slug' in columns:
        return ('slug',)
    return tuple(pk)


def collapse(table, rows, key):
    """Una fila por entidad: la de versión más nueva. Tercera auditoría (sobre
    e95a388): un clon nuevo aplicaba las filas en orden y, con un dump
    fusionado, podía quedarse con la versión vieja. Misma versión con
    contenido distinto: se aplica la última y se informa como conflicto."""
    if not key:
        return rows, []
    chosen, order, conflicts = {}, [], []
    for index, row in enumerate(rows):
        ident = tuple(row.get(c) for c in key)
        if any(v is None for v in ident):
            ident = ('__row__', index)
        if ident not in chosen:
            chosen[ident] = row
            order.append(ident)
            continue
        current = chosen[ident]
        if _version(row) > _version(current):
            chosen[ident] = row
        elif _version(row) == _version(current):
            strip = lambda r: {k: v for k, v in r.items() if k not in ('id', VERSION_COLUMN)}
            if strip(row) != strip(current):
                conflicts.append(f'{table}/{"/".join(str(v) for v in ident)}: misma versión con contenido distinto')
            chosen[ident] = row
    return [chosen[i] for i in order], conflicts


def apply_rows(con, rows):
    """Aplica las filas validadas dentro de la transacción que abrió quien
    llama (una sola: o todo o nada). La fila del dump reemplaza a la local con
    la misma PK o la misma clave natural. Devuelve (filas, conflictos)."""
    count, conflicts = 0, []
    tables_present = {r[0] for r in con.execute("SELECT name FROM sqlite_master WHERE type='table'")}
    for table in TABLES:
        if table not in rows:
            continue
        info = con.execute('PRAGMA table_info("%s")' % table).fetchall()
        if not info:
            raise ValueError('tabla ausente en la base local: ' + table)
        local = {r[1] for r in info}
        pk = [r[1] for r in sorted(info, key=lambda r: r[5]) if r[5] > 0]
        key = natural_key(table, local, pk)
        kept, found = collapse(table, rows[table], key)
        conflicts.extend(found)
        for original in kept:
            row = dict(original)
            version = row.pop(VERSION_COLUMN, None)
            unknown = set(row) - local
            if unknown:
                raise ValueError('%s: columnas desconocidas %s' % (table, sorted(unknown)))
            for columns in (pk, key):
                if columns and all(c in row for c in columns):
                    con.execute('DELETE FROM "%s" WHERE %s' % (table, ' AND '.join('"%s" IS ?' % c for c in columns)),
                                [row[c] for c in columns])
            names = ','.join('"%s"' % c for c in row)
            con.execute('INSERT INTO "%s" (%s) VALUES (%s)' % (table, names, ','.join('?' * len(row))), list(row.values()))
            if version and table in VERSIONED and 'memory_versions' in tables_present:
                con.execute('INSERT INTO memory_versions(table_name, slug, updated_at) VALUES (?,?,?) '
                            'ON CONFLICT(table_name, slug) DO UPDATE SET updated_at=excluded.updated_at',
                            (table, row.get('slug'), version))
            count += 1
    return count, conflicts
