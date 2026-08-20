#!/usr/bin/env bash
# teamdb-context-cache.sh — cache con TTL para contexto del proyecto
set -euo pipefail
PROJECT="${1:-$(pwd)}"
TTL_SECONDS="${2:-1800}"  # default 30 min
CACHE_FILE="$PROJECT/.opencode/context/.context-cache.json"

mkdir -p "$(dirname "$CACHE_FILE")"

if [ -f "$CACHE_FILE" ]; then
  age=$(($(date +%s) - $(stat -f%m "$CACHE_FILE" 2>/dev/null || stat -c%Y "$CACHE_FILE" 2>/dev/null)))
  if [ "$age" -lt "$TTL_SECONDS" ]; then
    cat "$CACHE_FILE"
    exit 0
  fi
fi

# Cache miss o expired: regenerar
CONTEXT=$(sqlite3 "$PROJECT/.opencode/context/team.db" "
  SELECT json_object(
    'concepts', (SELECT json_group_array(title) FROM concepts LIMIT 100),
    'decisions', (SELECT json_group_array(title) FROM decisions WHERE status='accepted' LIMIT 100),
    'preferences', (SELECT json_group_array(slug) FROM preferences LIMIT 50),
    'problems', (SELECT json_group_array(title) FROM known_problems WHERE status='open' LIMIT 50),
    'wip', (SELECT json_group_array(title) FROM work_in_progress WHERE status IN ('in_progress','in_review') LIMIT 50)
  )
" 2>/dev/null || echo '{}')

echo "$CONTEXT" > "$CACHE_FILE"
echo "$CONTEXT"