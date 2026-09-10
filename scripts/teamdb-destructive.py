#!/usr/bin/env python3
"""Private backend for the OpenCode tool that obtains native user approval first.

Never expose this script as an automatically allowed shell command.
"""
import hashlib
import json
from pathlib import Path
import sqlite3
import sys
import uuid

from teamdb_guard import words


def state_hash(conn):
    digest = hashlib.sha256()
    for line in conn.iterdump():
        digest.update(line.encode())
        digest.update(b'\n')
    return digest.hexdigest()


def operate(request):
    root = Path(request['project']).resolve()
    path = (root / request['database']).resolve()
    if not path.is_relative_to(root) or not path.is_file() or '.git' in path.relative_to(root).parts:
        raise ValueError('La base debe ser un archivo existente dentro del proyecto, fuera de .git.')
    sql = request['sql']
    params = request.get('params', [])
    tokens = words(sql)
    if not isinstance(params, list) or not tokens or tokens[0] not in ('delete', 'drop', 'alter', 'update', 'insert', 'replace'):
        raise ValueError('Se requiere una única operación SQL explícita y parámetros como lista.')
    if any(t in tokens for t in ('attach', 'detach', 'pragma', 'vacuum', 'load_extension')):
        raise ValueError('No se admite cambiar conexiones, archivos externos ni controles de SQLite.')
    applying = request.get('action') == 'apply'
    conn = sqlite3.connect(path.as_uri() + ('?mode=rw' if applying else '?mode=ro'), uri=True, timeout=5)
    backup = None
    try:
        conn.execute('PRAGMA foreign_keys=ON')
        conn.execute('BEGIN IMMEDIATE' if applying else 'BEGIN')
        digest = state_hash(conn)
        if not applying:
            # Compile without executing, detecting invalid SQL and multiple statements before asking.
            conn.execute('EXPLAIN ' + sql, params).fetchall()
            return {'database': str(path), 'state_hash': digest, 'sql': sql, 'params': params}
        if digest != request.get('state_hash'):
            raise ValueError('La base cambió después de presentar la operación. Se requiere nueva aprobación.')
        folder = root / '.opencode/context/.backups/approved-data-changes'
        if not folder.resolve().is_relative_to(root):
            raise ValueError('El directorio de respaldo está fuera del proyecto.')
        folder.mkdir(parents=True, exist_ok=True)
        backup = folder / (uuid.uuid4().hex + '.db')
        # An exclusive file prevents overwriting an earlier backup or following a symlink.
        with backup.open('xb'):
            pass
        backup.chmod(0o600)
        source = sqlite3.connect(path.as_uri() + '?mode=ro', uri=True)
        destination = sqlite3.connect(backup)
        try:
            source.backup(destination)
        finally:
            destination.close()
            source.close()
        cursor = conn.execute(sql, params)  # One statement only; rollback includes cascading effects.
        if cursor.description:
            for _ in cursor:
                pass  # Finish RETURNING statements before committing, without retaining their rows.
        conn.commit()
        return {'status': 'completed', 'changes': cursor.rowcount, 'backup': str(backup), 'database': str(path)}
    finally:
        conn.close()


if __name__ == '__main__':
    try:
        print(json.dumps(operate(json.load(sys.stdin)), ensure_ascii=False))
    except (ValueError, KeyError, sqlite3.Error, OSError) as error:
        print(json.dumps({'error': str(error)}), file=sys.stderr)
        sys.exit(1)
