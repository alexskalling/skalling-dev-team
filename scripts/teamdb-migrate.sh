#!/usr/bin/env bash
# teamdb-migrate.sh — Migra .jsonl/.md legacy a teamdb
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
export SKALLING_ROOT="$(dirname "$SCRIPT_DIR")"
source "$SCRIPT_DIR/lib/lib-teamdb.sh"

PROJECT="${1:-$(pwd)}"
teamdb_init_project "$PROJECT"
local_db="$(teamdb_project_path "$PROJECT")"
CTX_DIR="$PROJECT/.opencode/context"

# Migrar .jsonl
for jsonl in "$CTX_DIR"/*.jsonl; do
  [ -e "$jsonl" ] || continue
  fname=$(basename "$jsonl" .jsonl)
  case "$fname" in
    DECISIONS)
      while IFS= read -r line; do
        [ -n "$line" ] || continue
        topic=$(echo "$line" | python3 -c "import sys,json; print(json.loads(sys.stdin.read()).get('topic',''))" 2>/dev/null || echo "")
        decision=$(echo "$line" | python3 -c "import sys,json; print(json.loads(sys.stdin.read()).get('decision',''))" 2>/dev/null || echo "")
        [ -n "$topic" ] && sqlite3 "$local_db" "INSERT OR IGNORE INTO decisions (slug, title, body_md, decided_at) VALUES ('$topic', '$topic', '$decision', datetime('now'))"
      done < "$jsonl"
      ;;
    PATTERNS|PROJECT)
      while IFS= read -r line; do
        [ -n "$line" ] || continue
        name=$(echo "$line" | python3 -c "import sys,json; d=json.loads(sys.stdin.read()); print(d.get('name') or d.get('key',''))" 2>/dev/null || echo "")
        desc=$(echo "$line" | python3 -c "import sys,json; d=json.loads(sys.stdin.read()); print(d.get('description') or d.get('value') or d.get('note',''))" 2>/dev/null || echo "")
        [ -n "$name" ] && sqlite3 "$local_db" "INSERT OR IGNORE INTO concepts (slug, title, body_md, category, updated_at) VALUES ('$name', '$name', '$desc', 'legacy', datetime('now'))"
      done < "$jsonl"
      ;;
    PREFERENCES)
      while IFS= read -r line; do
        [ -n "$line" ] || continue
        slug=$(echo "$line" | python3 -c "import sys,json; print(json.loads(sys.stdin.read()).get('slug') or json.loads(sys.stdin.read()).get('scope',''))" 2>/dev/null || echo "")
        body=$(echo "$line" | python3 -c "import sys,json; print(json.loads(sys.stdin.read()).get('preference',''))" 2>/dev/null || echo "")
        [ -n "$slug" ] && sqlite3 "$local_db" "INSERT OR IGNORE INTO preferences (slug, scope, body_md, source) VALUES ('$slug', 'legacy', '$body', 'migrated')"
      done < "$jsonl"
      ;;
    REJECTIONS)
      while IFS= read -r line; do
        [ -n "$line" ] || continue
        attempted=$(echo "$line" | python3 -c "import sys,json; print(json.loads(sys.stdin.read()).get('attempted',''))" 2>/dev/null || echo "")
        reason=$(echo "$line" | python3 -c "import sys,json; print(json.loads(sys.stdin.read()).get('reason',''))" 2>/dev/null || echo "")
        [ -n "$attempted" ] && sqlite3 "$local_db" "INSERT OR IGNORE INTO known_problems (slug, title, symptom_md, discovered_at) VALUES ('$attempted', '$attempted', '$reason', datetime('now'))"
      done < "$jsonl"
      ;;
  esac
done

# Migrar .md
for md in "$CTX_DIR/concept/"*.md; do
  [ -e "$md" ] || continue
  fname=$(basename "$md" .md)
  body=$(cat "$md" | sed "s/'/''/g")
  sqlite3 "$local_db" "INSERT OR IGNORE INTO concepts (slug, title, body_md, category, updated_at) VALUES ('$fname', '$fname', '$body', 'concept', datetime('now'))"
done

# Mover legacy
LEGACY="$CTX_DIR/legacy"
mkdir -p "$LEGACY"
[ -d "$CTX_DIR/concept" ] && mv "$CTX_DIR/concept" "$LEGACY/" 2>/dev/null || true
[ -d "$CTX_DIR/decisiones" ] && mv "$CTX_DIR/decisiones" "$LEGACY/" 2>/dev/null || true
mv "$CTX_DIR"/*.jsonl "$LEGACY/" 2>/dev/null || true

echo "migrated: $local_db"
