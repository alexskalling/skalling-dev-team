#!/usr/bin/env bash
# wip-tree.sh — Visualiza plan/feature/task
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/lib/lib-teamdb.sh"

PROJECT="${1:-$(pwd)}"
local_db="$(teamdb_project_path "$PROJECT")"
[ -f "$local_db" ] || { echo "no DB: $local_db" >&2; exit 1; }

status_icon() {
  case "$1" in
    resolved) echo "✅" ;;
    in_progress) echo "🟡" ;;
    in_review) echo "🔵" ;;
    approved) echo "🟢" ;;
    rejected) echo "🔴" ;;
    abandoned) echo "⚫" ;;
    *) echo "⚪" ;;
  esac
}

print_children() {
  local indent="$1"
  local parent_slug="$2"

  local children
  children=$(sqlite3 -separator $'\t' "$local_db" "SELECT slug, title, type, status, owner FROM work_in_progress WHERE parent_id = (SELECT id FROM work_in_progress WHERE slug='$parent_slug') ORDER BY priority, created_at")

  while IFS=$'\t' read -r cslug ctitle ctype cstatus cowner; do
    [ -z "$cslug" ] && continue
    local icon; icon=$(status_icon "$cstatus")
    local detail=""
    [ -n "$cowner" ] && detail=" @${cowner}"
    echo "${indent}${icon} ${ctype}: ${ctitle}${detail}"
    print_children "${indent}  " "$cslug"
  done <<< "$children"
}

render_tree() {
  local roots
  roots=$(sqlite3 -separator $'\t' "$local_db" "SELECT slug, title, type, status FROM work_in_progress WHERE parent_id IS NULL ORDER BY type='plan' DESC, created_at DESC")

  while IFS=$'\t' read -r rslug rtitle rtype rstatus; do
    [ -z "$rslug" ] && continue
    local icon
    icon=$(status_icon "$rstatus")
    if [ "$rtype" = "plan" ]; then
      echo "${icon} 📋 PLAN: ${rtitle}"
      print_children "│   " "$rslug"
    else
      echo "${icon} ⚠️  ${rtype}: ${rtitle}"
      print_children "   " "$rslug"
    fi
    echo ""
  done <<< "$roots"
}

echo "📋 Work In Progress"
render_tree
