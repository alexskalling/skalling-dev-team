"""SQLite safety for preauthorized helpers. This is not an OS sandbox."""
import re
import sqlite3

MESSAGE = 'DATA_APPROVAL_REQUIRED: operación con pérdida de datos; usar teamdb_destructive con aprobación explícita.'
# Runtime state is mutable; durable project knowledge keeps previous versions.
DURABLE = {'concepts', 'decisions', 'preferences', 'known_problems', 'plans', 'tasks',
           'proposals', 'specs', 'design_notes', 'memory_links', 'task_dependencies', 'work_in_progress'}
CONTENT = {'title', 'body_md', 'symptom_md', 'workaround_md', 'intent_md', 'design_md',
           'purpose', 'acceptance', 'acceptance_md', 'description', 'slug'}


def words(sql):
    # Ignore comments and quoted values, so documentation containing DELETE is data.
    clean = re.sub(r"--[^\n]*(?:\n|$)|/\*.*?\*/|'(?:''|[^'])*'|\"(?:\"\"|[^\"])*\"|`[^`]*`|\[[^]]*\]", ' ', sql, flags=re.S)
    return re.findall(r'[A-Za-z_]+', clean.lower())


def validate(sql):
    tokens = words(sql)
    if not tokens:
        raise sqlite3.DatabaseError(MESSAGE)
    if any(t in tokens for t in ('delete', 'replace', 'drop', 'attach', 'detach', 'vacuum')):
        raise sqlite3.DatabaseError(MESSAGE)
    if 'alter' in tokens and ('add' not in tokens or 'rename' in tokens):
        raise sqlite3.DatabaseError(MESSAGE)
    if tokens[0] == 'pragma' and any(t in tokens for t in ('writable_schema', 'ignore_check_constraints', 'recursive_triggers')):
        raise sqlite3.DatabaseError(MESSAGE)


class GuardedCursor(sqlite3.Cursor):
    def execute(self, sql, parameters=()):
        validate(sql)
        return super().execute(sql, parameters)

    def executemany(self, sql, parameters):
        validate(sql)
        return super().executemany(sql, parameters)

    def executescript(self, sql):
        raise sqlite3.DatabaseError(MESSAGE)


class GuardedConnection(sqlite3.Connection):
    def cursor(self, factory=GuardedCursor):
        return super().cursor(factory)

    def execute(self, sql, parameters=()):
        validate(sql)
        return super().execute(sql, parameters)

    def executemany(self, sql, parameters):
        validate(sql)
        return super().executemany(sql, parameters)

    def executescript(self, sql):
        # Runtime helpers use bound single statements; migration scripts are separately approved.
        raise sqlite3.DatabaseError(MESSAGE)


def connect(database, *args, readonly=False, **kwargs):
    if kwargs.get('uri') and 'mode=ro' in str(database):
        conn = sqlite3.connect(database, *args, **kwargs)
        conn.execute('PRAGMA query_only=ON')
        return conn
    if readonly:
        from pathlib import Path
        conn = sqlite3.connect(Path(database).resolve().as_uri() + '?mode=ro', uri=True, *args, **kwargs)
        conn.execute('PRAGMA query_only=ON')
        return conn
    conn = sqlite3.connect(database, *args, factory=GuardedConnection, **kwargs)
    try:
        tables = {r[1]: r[2] for r in conn.execute('PRAGMA table_list')}
        shadows = {name for name, kind in tables.items() if kind == 'shadow'}
        durable = DURABLE.intersection(tables)
        if durable:
            conn.execute('''CREATE TABLE IF NOT EXISTS data_revisions(
                id INTEGER PRIMARY KEY, table_name TEXT NOT NULL, row_key TEXT,
                previous_json TEXT NOT NULL, changed_at TEXT NOT NULL DEFAULT CURRENT_TIMESTAMP)''')
        for table in sorted(durable):
            columns = [r[1] for r in conn.execute(f'PRAGMA table_info("{table}")')]
            quoted = lambda c: '"' + c.replace('"', '""') + '"'
            pairs = ','.join("'" + c.replace("'", "''") + "',OLD." + quoted(c) for c in columns)
            changed = ' OR '.join('OLD.' + quoted(c) + ' IS NOT NEW.' + quoted(c) for c in columns)
            key = 'OLD.' + quoted('id' if 'id' in columns else columns[0])
            conn.execute(f'''CREATE TEMP TRIGGER "safety_history_{table}" BEFORE UPDATE ON "{table}" WHEN {changed}
                BEGIN INSERT INTO data_revisions(table_name,row_key,previous_json)
                VALUES('{table}',{key},json_object({pairs})); END''')
            for column in CONTENT.intersection(columns):
                col = quoted(column)
                conn.execute(f'''CREATE TEMP TRIGGER "safety_content_{table}_{column}" BEFORE UPDATE OF {col} ON "{table}"
                    WHEN OLD.{col} IS NOT NULL AND trim(CAST(OLD.{col} AS TEXT)) != ''
                    AND (NEW.{col} IS NULL OR trim(CAST(NEW.{col} AS TEXT)) = '')
                    BEGIN SELECT RAISE(ABORT, '{MESSAGE}'); END''')

        def authorize(action, first, second, db_name, source):
            if action in (sqlite3.SQLITE_ATTACH, sqlite3.SQLITE_DETACH,
                          sqlite3.SQLITE_DROP_TABLE, sqlite3.SQLITE_DROP_VTABLE,
                          sqlite3.SQLITE_DROP_TEMP_TABLE, sqlite3.SQLITE_DROP_TRIGGER,
                          sqlite3.SQLITE_DROP_TEMP_TRIGGER):
                return sqlite3.SQLITE_DENY
            if action == sqlite3.SQLITE_DELETE and first not in shadows:
                return sqlite3.SQLITE_DENY
            if action == sqlite3.SQLITE_UPDATE and first == 'data_revisions':
                return sqlite3.SQLITE_DENY
            if action == sqlite3.SQLITE_FUNCTION and second == 'load_extension':
                return sqlite3.SQLITE_DENY
            return sqlite3.SQLITE_OK
        conn.set_authorizer(authorize)
        return conn
    except Exception:
        conn.close()
        raise
