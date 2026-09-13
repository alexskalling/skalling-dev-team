#!/usr/bin/env python3
"""Archive legacy memory reversibly, or explicitly export a TeamDB concept."""
import argparse
import datetime
import hashlib
import json
import shutil
import sqlite3
from pathlib import Path


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument('--project', required=True)
    action = parser.add_mutually_exclusive_group(required=True)
    action.add_argument('--archive-legacy', action='store_true')
    action.add_argument('--export-concept')
    args = parser.parse_args()
    project = Path(args.project).resolve()
    context = project / '.opencode/context'
    db_path = context / 'team.db'
    if not db_path.is_file():
        raise SystemExit('TeamDB no existe; no se mueve ningún archivo')
    with sqlite3.connect(db_path, timeout=10) as db:
        if args.export_concept:
            slug = args.export_concept
            if not slug or any(c not in 'abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789-_' for c in slug):
                raise SystemExit('Slug inválido')
            row = db.execute('SELECT body_md FROM concepts WHERE slug=?', (slug,)).fetchone()
            if not row:
                raise SystemExit('Concepto no encontrado')
            target = project / '.opencode/exports' / (slug + '.md')
            target.parent.mkdir(parents=True, exist_ok=True)
            target.write_text('<!-- GENERATED from TeamDB; edit the database, not this export. -->\n' + row[0], encoding='utf-8')
            print(target)
            return
        names = ('stack', 'proyecto', 'decisiones', 'preferencias', 'problemas-conocidos',
                 'trabajo-en-curso', 'index.md', 'log.md', 'README.md')
        targets = [context / name for name in names if (context / name).exists()]
        if not targets:
            print(json.dumps({'archived': 0}))
            return
        files = []
        for target in targets:
            if target.is_symlink():
                raise SystemExit('No se archivan enlaces simbólicos: ' + str(target))
            entries = list(target.rglob('*')) if target.is_dir() else [target]
            if any(p.is_symlink() for p in entries):
                raise SystemExit('No se archivan árboles con enlaces simbólicos')
            files.extend(p for p in entries if p.is_file())
        stamp = datetime.datetime.now(datetime.timezone.utc).strftime('%Y%m%dT%H%M%S%fZ')
        backup = context / '.backups' / ('legacy-memory-' + stamp)
        # Commit an exact byte copy before moving anything. Archived documents are
        # historical evidence, never silently promoted to accepted decisions.
        with db:
            db.execute('CREATE TABLE IF NOT EXISTS legacy_documents (path TEXT, sha256 TEXT, content BLOB NOT NULL, archived_at TEXT NOT NULL, PRIMARY KEY(path,sha256))')
            for path in files:
                content = path.read_bytes()
                digest = hashlib.sha256(content).hexdigest()
                db.execute('INSERT OR IGNORE INTO legacy_documents VALUES(?,?,?,?)',
                           (str(path.relative_to(context)), digest, content, stamp))
        backup.mkdir(parents=True, exist_ok=False)
        for target in targets:
            shutil.move(str(target), str(backup / target.name))
        print(json.dumps({'archived': len(files), 'backup': str(backup), 'copy_in_db': 'legacy_documents'}))


if __name__ == '__main__':
    main()
