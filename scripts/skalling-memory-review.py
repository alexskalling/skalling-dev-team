"""Read-only review of TeamDB. Findings are candidates, never deletions."""
from contextlib import closing
import collections
from pathlib import Path
import sqlite3
import sys


def review(path):
    with closing(sqlite3.connect(Path(path).resolve().as_uri() + '?mode=ro', uri=True)) as conn:
        conn.row_factory = sqlite3.Row
        print('TeamDB: candidatos para revisión humana; antigüedad no demuestra obsolescencia.')
        for table, content, date in [('concepts', 'body_md', 'updated_at'),
                                     ('decisions', 'body_md', 'decided_at'),
                                     ('preferences', 'body_md', None),
                                     ('known_problems', 'symptom_md', 'discovered_at')]:
            groups = collections.defaultdict(list)
            for row in conn.execute(f'SELECT * FROM {table}'):
                body = ' '.join((row[content] or '').split())
                if body:
                    groups[body].append(row['slug'])
            for slugs in groups.values():
                if len(slugs) > 1:
                    print(f'Duplicados de contenido ({table}): ' + ', '.join(slugs))
            if date:
                for row in conn.execute(f"SELECT slug FROM {table} WHERE {date} < datetime('now','-6 months') LIMIT 100"):
                    print(f'Revisar vigencia ({table}): {row[0]}')
        for row in conn.execute("SELECT slug FROM work_in_progress WHERE status IN ('open','in_progress','in_review') "
                                "AND updated_at < datetime('now','-30 days') LIMIT 100"):
            print('WIP sin actualización reciente: ' + row[0])
        for row in conn.execute("SELECT slug FROM decisions WHERE status='superseded' LIMIT 100"):
            print('Decisión reemplazada (se conserva): ' + row[0])
        print('Revisión de TeamDB terminada; no se borraron ni modificaron recuerdos.')


if __name__ == '__main__':
    try:
        review(sys.argv[1])
    except (OSError, ValueError, sqlite3.Error) as exc:
        sys.exit('ERROR: revisión incompleta: ' + str(exc))
