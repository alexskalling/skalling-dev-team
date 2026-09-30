#!/usr/bin/env bash
set -euo pipefail

KEEP="${SKALLING_TEAMDB_BACKUPS_KEEP:-5}"
PROJECT="$(pwd)"
DRY_RUN=false

while [ "$#" -gt 0 ]; do
  case "$1" in
    --keep) KEEP="${2:-}"; shift 2 ;;
    --dry-run) DRY_RUN=true; shift ;;
    *) PROJECT="$1"; shift ;;
  esac
done

case "$KEEP" in
  ''|*[!0-9]*) echo "ERROR: --keep debe ser un entero" >&2; exit 2 ;;
esac

# Solo nombres de backup propios; nunca recursivo ni enlaces simbólicos.
python3 - "$PROJECT" "$KEEP" "$DRY_RUN" <<'PYPRUNE'
from pathlib import Path
import sys
project, keep, dry = Path(sys.argv[1]), int(sys.argv[2]), sys.argv[3] == 'true'
families = [(project/'.opencode/context/.backups', 'team.db.backup-*'),
            (project/'.opencode/context', 'team.db.pre-migration-*')]
for directory, pattern in families:
    files = sorted((p for p in directory.glob(pattern) if p.is_file() and not p.is_symlink()),
                   key=lambda p: (p.stat().st_mtime_ns, p.name), reverse=True)
    for path in files[keep:]:
        if dry:
            print('[dry-run] retiraría', path)
        else:
            path.unlink()
    print(f'teamdb backups: {min(keep, len(files))} conservados; {max(0,len(files)-keep)} ' +
          ('candidatos' if dry else 'retirados') + f' ({pattern})')
PYPRUNE
