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

BACKUP_DIR="$PROJECT/.opencode/context/.backups"
[ -d "$BACKUP_DIR" ] || exit 0

COUNT="$(find "$BACKUP_DIR" -maxdepth 1 -type f -name 'team.db.backup-*' | wc -l | tr -d ' ')"
if [ "$COUNT" -le "$KEEP" ]; then
  printf 'teamdb backups: %s conservados (límite %s)\n' "$COUNT" "$KEEP"
  exit 0
fi

DELETE_COUNT=$((COUNT - KEEP))
find "$BACKUP_DIR" -maxdepth 1 -type f -name 'team.db.backup-*' -print \
  | sort \
  | head -n "$DELETE_COUNT" \
  | while IFS= read -r backup; do
      case "$backup" in
        "$BACKUP_DIR"/team.db.backup-*)
          if [ "$DRY_RUN" = true ]; then
            printf '[dry-run] retiraría %s\n' "$backup"
          else
            rm -f -- "$backup"
          fi
          ;;
        *) echo "ERROR: ruta de backup inesperada: $backup" >&2; exit 1 ;;
      esac
    done

printf 'teamdb backups: %s retirados; se conservan %s\n' "$DELETE_COUNT" "$KEEP"
