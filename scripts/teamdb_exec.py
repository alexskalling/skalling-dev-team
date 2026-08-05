#!/usr/bin/env python3
"""teamdb_exec.py — Wrapper Python sobre sqlite3 con real parameter binding.

Reemplaza teamdb_safe_query (que usaba escape manual de '). El CLI sqlite3 no
soporta bind de ?/?N/:name; Python sqlite3 sí.

Modos:
  query       — SELECT (read-only), retorna rows como JSON
  write       — INSERT/UPDATE/DELETE, retorna {changes, lastrowid}
  transaction — BEGIN IMMEDIATE + single SQL + commit (atomicidad portable)
  raw         — ejecuta SQL sin bind (SOLO para DDL/migrations; rechaza DML)

Uso:
  python3 scripts/teamdb_exec.py --db <path> --mode query \\
    --sql "SELECT * FROM x WHERE a = ?" --params '["v1","v2"]'

PRAGMA aplicados: journal_mode=WAL, busy_timeout, foreign_keys=ON
"""
import sqlite3
import sys
import json
import argparse

DML_DANGEROUS = ("drop", "delete", "update", "insert", "replace",
                 "alter", "truncate", "attach", "detach")
DDL_BENIGN_PREFIXES = ("create", "select", "with", "pragma", "explain",
                        "vacuum", "reindex", "analyze")


def _raw_is_safe(sql):
    s = sql.strip().lower()
    if any(s.startswith(d) for d in DML_DANGEROUS):
        return False
    if not any(s.startswith(d) for d in DDL_BENIGN_PREFIXES):
        return False
    return True


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument('--db', required=True)
    ap.add_argument('--mode', choices=['query', 'write', 'transaction', 'raw', 'multi'],
                    default='query')
    ap.add_argument('--sql', required=True)
    ap.add_argument('--params', default='[]')
    ap.add_argument('--params-batches', default='[]',
                    help='For mode=multi: JSON array of arrays, one per statement')
    ap.add_argument('--timeout', type=int, default=5000)
    args = ap.parse_args()

    try:
        params = json.loads(args.params)
        if not isinstance(params, list):
            params = [params]
    except Exception as e:
        json.dump({'error': 'bad params JSON: {}'.format(e)}, sys.stdout)
        sys.exit(1)

    conn = sqlite3.connect(args.db, timeout=args.timeout / 1000)
    conn.row_factory = sqlite3.Row

    try:
        conn.execute('PRAGMA journal_mode=WAL')
    except Exception:
        pass
    try:
        conn.execute('PRAGMA busy_timeout={}'.format(args.timeout))
    except Exception:
        pass
    try:
        conn.execute('PRAGMA foreign_keys=ON')
    except Exception:
        pass

    try:
        if args.mode == 'query':
            cur = conn.execute(args.sql, params)
            rows = [dict(r) for r in cur.fetchall()]
            json.dump(rows, sys.stdout, default=str)
        elif args.mode == 'write':
            conn.execute('BEGIN IMMEDIATE')
            try:
                cur = conn.execute(args.sql, params)
                conn.commit()
                json.dump({'changes': cur.rowcount, 'lastrowid': cur.lastrowid},
                          sys.stdout)
            except Exception:
                conn.rollback()
                raise
        elif args.mode == 'transaction':
            conn.execute('BEGIN IMMEDIATE')
            try:
                cur = conn.execute(args.sql, params)
                conn.commit()
                json.dump([{'changes': cur.rowcount, 'lastrowid': cur.lastrowid}],
                          sys.stdout)
            except Exception:
                conn.rollback()
                raise
        elif args.mode == 'raw':
            if not _raw_is_safe(args.sql):
                json.dump({'error': 'raw mode no acepta este SQL (DML/DDL destructivo)'},
                          sys.stdout)
                sys.exit(2)
            cur = conn.execute(args.sql)
            rows = [dict(r) for r in cur.fetchall()]
            conn.commit()
            json.dump(rows, sys.stdout, default=str)
        elif args.mode == 'multi':
            # Multi-statement atómico: lista de (sql, params[]) en una sola transacción
            try:
                batches = json.loads(args.params_batches)
            except Exception as e:
                json.dump({'error': 'bad params_batches JSON: {}'.format(e)}, sys.stdout)
                sys.exit(1)
            if not isinstance(batches, list) or not batches:
                json.dump({'error': 'params_batches debe ser lista no vacía'}, sys.stdout)
                sys.exit(1)
            conn.execute('BEGIN IMMEDIATE')
            try:
                results = []
                for batch in batches:
                    sql_i = batch.get('sql', '')
                    params_i = batch.get('params', [])
                    cur = conn.execute(sql_i, params_i)
                    results.append({
                        'changes': cur.rowcount,
                        'lastrowid': cur.lastrowid,
                    })
                conn.commit()
                json.dump(results, sys.stdout)
            except Exception:
                conn.rollback()
                raise
    except Exception as e:
        try:
            conn.rollback()
        except Exception:
            pass
        json.dump({'error': str(e), 'mode': args.mode}, sys.stdout)
        sys.exit(1)
    finally:
        conn.close()


if __name__ == '__main__':
    main()
