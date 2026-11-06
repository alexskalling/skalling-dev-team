"""Connection policy shared by TeamDB readers, guarded helpers and runtime writers.

WAL is established by initialization, not changed on every read. This module
sets connection-local guarantees; authorization remains in teamdb_guard.
"""
from pathlib import Path
import sqlite3


def connect(database, *args, readonly=False, create=False, **kwargs):
    kwargs.setdefault('timeout', 10)
    if str(database) != ':memory:' and not kwargs.get('uri'):
        mode = 'ro' if readonly else 'rwc' if create else 'rw'
        database = Path(database).resolve().as_uri() + '?mode=' + mode
        kwargs['uri'] = True
    conn = sqlite3.connect(database, *args, **kwargs)
    try:
        conn.execute('PRAGMA foreign_keys=ON')
        if conn.execute('PRAGMA foreign_keys').fetchone()[0] != 1:
            raise sqlite3.DatabaseError('TeamDB requires foreign key enforcement')
        if readonly or (kwargs.get('uri') and 'mode=ro' in str(database)):
            conn.execute('PRAGMA query_only=ON')
        return conn
    except BaseException:
        conn.close()
        raise
