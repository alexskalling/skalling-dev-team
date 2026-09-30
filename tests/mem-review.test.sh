#!/usr/bin/env bash
# Review the current TeamDB store, never silently succeed without a database.
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
FIXTURE="$(mktemp -d)"
trap 'rm -rf "$FIXTURE"' EXIT
if bash "$ROOT/scripts/mem-review.sh" --target "$FIXTURE" >/dev/null 2>&1; then
  echo 'FAIL: revisión sin DB no puede ser exitosa'; exit 1
fi
mkdir -p "$FIXTURE/.opencode/context"
DB="$FIXTURE/.opencode/context/team.db"
sqlite3 "$DB" < "$ROOT/sql/project-schema.sql"
sqlite3 "$DB" <<'SQL'
INSERT INTO concepts(slug,title,body_md,updated_at) VALUES ('a','A','igual','2020-01-01'),('b','B','igual','2020-01-01');
INSERT INTO work_in_progress(slug,title,status,updated_at) VALUES ('zombie','Pendiente','open','2020-01-01'),('closed','Finalizado','resolved','2020-01-01');
INSERT INTO decisions(slug,title,body_md,status,decided_at) VALUES ('old','Vieja','Reemplazada','superseded','2020-01-01');
SQL
BEFORE="$(shasum -a 256 "$DB")"
OUTPUT="$(bash "$ROOT/scripts/mem-review.sh" --target "$FIXTURE" --dry-run)"
grep -q 'Duplicados de contenido (concepts): a, b' <<< "$OUTPUT"
grep -q 'WIP sin actualización reciente: zombie' <<< "$OUTPUT"
! grep -q 'WIP sin actualización reciente: closed' <<< "$OUTPUT"
grep -q 'Decisión reemplazada (se conserva): old' <<< "$OUTPUT"
[ "$BEFORE" = "$(shasum -a 256 "$DB")" ]
echo 'PASS: revisa TeamDB, distingue WIP cerrado y conserva los bytes de la base'
