"""Expose recorded memory conflicts in bounded batches; never infer truth from prose."""
TABLES = {'concepts', 'decisions', 'preferences', 'known_problems'}


def annotate_relations(db, entries):
    if not entries or not db.execute("SELECT 1 FROM sqlite_master WHERE name='memory_links'").fetchone():
        return
    selected, identities = {}, {}
    for table in TABLES:
        items = {item['slug']: item for kind, item in entries if kind == table}
        if not items:
            continue
        marks = ','.join('?' for _ in items)
        for ident, slug in db.execute(f'SELECT id,slug FROM {table} WHERE slug IN ({marks})', tuple(items)):
            selected[table, ident] = items[slug]
            identities[table, ident] = {'table': table, 'slug': slug}
    if not selected:
        return
    clauses, args = [], []
    for table in TABLES:
        ids = [ident for kind, ident in selected if kind == table]
        if ids:
            marks = ','.join('?' for _ in ids)
            clauses += [f'(from_table=? AND from_id IN ({marks}))', f'(to_table=? AND to_id IN ({marks}))']
            args += [table, *ids, table, *ids]
    links = db.execute("SELECT from_table,from_id,to_table,to_id,link_type,confidence FROM memory_links "
                       "WHERE link_type IN ('contradicts','supersedes') AND (" + ' OR '.join(clauses) +
                       ') ORDER BY id LIMIT 129', args).fetchall()
    overflow = len(links) > 128
    links = links[:128]
    endpoints = {(table, ident) for a, b, c, d, _, _ in links for table, ident in ((a, b), (c, d))}
    active = set()
    for table in TABLES:
        ids = [ident for kind, ident in endpoints if kind == table]
        if not ids:
            continue
        guard = " AND status='accepted'" if table == 'decisions' else " AND status='open'" if table == 'known_problems' else ''
        marks = ','.join('?' for _ in ids)
        for ident, slug in db.execute(f'SELECT id,slug FROM {table} WHERE id IN ({marks})' + guard, ids):
            active.add((table, ident))
            identities[table, ident] = {'table': table, 'slug': slug}
    for a, b, c, d, relation, confidence in links:
        left, right = (a, b), (c, d)
        # A retired decision must not create a new unresolved conflict.
        if left not in active or right not in active:
            continue
        for own, other, incoming in ((left, right, False), (right, left, True)):
            item = selected.get(own)
            if item is None:
                continue
            notes = item.setdefault('relations', [])
            if len(notes) >= 4:
                item['relations_truncated'] = True
            else:
                notes.append({'type': 'superseded_by' if relation == 'supersedes' and incoming else relation,
                              'target': identities[other], 'confidence': confidence})
            if relation == 'contradicts' or incoming:
                item['requires_resolution'] = True
    if overflow:
        for item in selected.values():
            item['relations_truncated'] = True
            item['requires_resolution'] = True
