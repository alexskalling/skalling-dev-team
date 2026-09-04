#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

bash "$ROOT/scripts/teamdb-init.sh" "$TMP" >/dev/null
DB="$TMP/.opencode/context/team.db"
sqlite3 "$DB" <<'SQL'
INSERT INTO plans(slug,title,design_md,status,created_at,updated_at)
VALUES('checkout','Checkout seguro','Diseño','in_progress',datetime('now'),datetime('now'));
INSERT INTO tasks(plan_id,slug,title,status,owner,blocked_reason,order_index)
SELECT id,'payment-api','Integrar pagos','blocked','teo','Falta sandbox',1 FROM plans WHERE slug='checkout';
INSERT INTO tasks(plan_id,slug,title,status,owner,order_index)
SELECT id,'receipt','Crear recibo','pending','pau',2 FROM plans WHERE slug='checkout';
UPDATE workflow_state SET active_cycle_slug='checkout',phase='build',actor='teo',updated_at=datetime('now') WHERE id=1;
SQL

OUT="$(bash "$ROOT/scripts/teamdb-resume.sh" "$TMP")"
grep -q 'checkout' <<< "$OUT"
grep -q 'payment-api' <<< "$OUT"
grep -q 'Falta sandbox' <<< "$OUT"
grep -q 'Siguiente' <<< "$OUT"
[ "$(printf '%s' "$OUT" | wc -c | tr -d ' ')" -lt 3000 ]
echo "PASS: resume devuelve una cápsula breve y accionable"
