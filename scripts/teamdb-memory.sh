#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# Ruta de TeamDB: la del repositorio principal, también desde un worktree.
# shellcheck disable=SC1091
if [ -f "$SCRIPT_DIR/lib-teamdb.sh" ]; then . "$SCRIPT_DIR/lib-teamdb.sh"; else . "$SCRIPT_DIR/lib/lib-teamdb.sh"; fi
PROJECT="${PROJECT:-$(pwd)}"

if [ "${1:-}" = "--project" ]; then
  PROJECT="${2:?Falta project}"
  shift 2
fi

KIND="${1:-}"
shift || true
DB="$(teamdb_project_path "$PROJECT")"
[ -f "$DB" ] || { echo "ERROR: DB no existe: $DB" >&2; exit 1; }

# One guarded transaction, including batch; export once after it commits.
TEAMDB_ACTOR="${TEAMDB_ACTOR:-pau}" python3 "$SCRIPT_DIR/skalling-memory-write.py" "$DB" "$KIND" "$@"
# Always refresh: also repairs an export interrupted after an earlier commit.
if [ -f "$SCRIPT_DIR/teamdb-dump.sh" ]; then
  bash "$SCRIPT_DIR/teamdb-dump.sh" "$PROJECT" >/dev/null
fi
