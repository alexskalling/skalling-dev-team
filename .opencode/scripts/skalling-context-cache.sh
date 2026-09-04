#!/usr/bin/env bash
# skalling-context-cache.sh — Cache de contexto de proyecto (1 build + N hits)
# Uso: skalling-context-cache.sh [project-dir]
# Output: JSON completo del contexto a stdout

set -euo pipefail

PROJECT="${1:-$(pwd)}"
CACHE_FILE="$PROJECT/.opencode/context/.project-context-cache.json"
DB="$PROJECT/.opencode/context/team.db"
YAML_FILE="$PROJECT/.opencode/project.yaml"
TTL_SECONDS=3600

# Helper: leer cache si existe y es válido
read_cache_if_valid() {
    [[ -f "$CACHE_FILE" ]] || return 1
    
    # 1. TTL
    local cache_age=$(($(date +%s) - $(stat -c %Y "$CACHE_FILE" 2>/dev/null || stat -f %m "$CACHE_FILE")))
    [[ $cache_age -lt $TTL_SECONDS ]] || return 1
    
    # 2. project.yaml mtime
    [[ -f "$YAML_FILE" ]] || return 1
    local yaml_mtime=$(stat -c %Y "$YAML_FILE" 2>/dev/null || stat -f %m "$YAML_FILE")
    local cache_yaml_mtime=$(jq -r '.project_yaml_mtime // 0' "$CACHE_FILE" 2>/dev/null || echo 0)
    [[ "$yaml_mtime" -eq "$cache_yaml_mtime" ]] || return 1
    
    # 3. DB counts (concepts + decisions)
    [[ -f "$DB" ]] || return 1
    local db_concepts=$(sqlite3 "$DB" "SELECT COUNT(*) FROM concepts" 2>/dev/null || echo -1)
    local db_decisions=$(sqlite3 "$DB" "SELECT COUNT(*) FROM decisions" 2>/dev/null || echo -1)
    local cache_concepts=$(jq -r '.db_counts.concepts // -1' "$CACHE_FILE" 2>/dev/null || echo -1)
    local cache_decisions=$(jq -r '.db_counts.decisions // -1' "$CACHE_FILE" 2>/dev/null || echo -1)
    [[ "$db_concepts" -eq "$cache_concepts" && "$db_decisions" -eq "$cache_decisions" ]] || return 1
    
    # Cache válido
    cat "$CACHE_FILE"
    return 0
}

# Helper: construir cache fresco
build_cache() {
    mkdir -p "$(dirname "$CACHE_FILE")"
    
    # project.yaml
    local yaml_content="{}"
    [[ -f "$YAML_FILE" ]] && yaml_content=$(cat "$YAML_FILE")
    local language=$(echo "$yaml_content" | yq -r '.stack.language // "typescript"' 2>/dev/null || echo "typescript")
    local framework=$(echo "$yaml_content" | yq -r '.stack.framework // "nextjs"' 2>/dev/null || echo "nextjs")
    local test_runner=$(echo "$yaml_content" | yq -r '.stack.test_runner // "vitest"' 2>/dev/null || echo "vitest")
    local has_ui=$(echo "$yaml_content" | yq -r '.has_ui // false' 2>/dev/null || echo "false")
    
    # DB queries
    local design_system_md=""
    local concepts_by_cat="{}"
    local decisions_accepted="[]"
    local problems_open="[]"
    local db_concepts=0
    local db_decisions=0
    local db_prefs=0
    
    if [[ -f "$DB" ]]; then
        design_system_md=$(sqlite3 "$DB" "SELECT body_md FROM concepts WHERE slug='design-system'" 2>/dev/null || echo "")
        db_concepts=$(sqlite3 "$DB" "SELECT COUNT(*) FROM concepts" 2>/dev/null || echo 0)
        db_decisions=$(sqlite3 "$DB" "SELECT COUNT(*) FROM decisions" 2>/dev/null || echo 0)
        db_prefs=$(sqlite3 "$DB" "SELECT COUNT(*) FROM preferences" 2>/dev/null || echo 0)
        
        concepts_by_cat=$(sqlite3 "$DB" "SELECT category, COUNT(*) FROM concepts GROUP BY category" 2>/dev/null | \
            jq -R 'split("|") | {key: .[0], value: .[1]|tonumber}' | jq -s 'from_entries' || echo "{}")
        
        decisions_accepted=$(sqlite3 "$DB" "SELECT slug, title FROM decisions WHERE status='accepted'" 2>/dev/null | \
            jq -R 'split("|") | {slug: .[0], title: .[1]}' | jq -s '.' || echo "[]")
        
        problems_open=$(sqlite3 "$DB" "SELECT slug, title, workaround_md FROM known_problems WHERE status='open'" 2>/dev/null | \
            jq -R 'split("|") | {slug: .[0], title: .[1], workaround: .[2]}' | jq -s '.' || echo "[]")
    fi
    
    local yaml_mtime=0
    [[ -f "$YAML_FILE" ]] && yaml_mtime=$(stat -c %Y "$YAML_FILE" 2>/dev/null || stat -f %m "$YAML_FILE")
    
    # Build JSON
    jq -n \
      --arg language "$language" \
      --arg framework "$framework" \
      --arg test_runner "$test_runner" \
      --argjson has_ui "$has_ui" \
      --arg design_system_md "$design_system_md" \
      --argjson concepts_by_cat "$concepts_by_cat" \
      --argjson decisions_accepted "$decisions_accepted" \
      --argjson problems_open "$problems_open" \
      --argjson db_concepts "$db_concepts" \
      --argjson db_decisions "$db_decisions" \
      --argjson db_prefs "$db_prefs" \
      --argjson yaml_mtime "$yaml_mtime" \
      --arg generated_at "$(date -u +%Y-%m-%dT%H:%M:%SZ)" \
    '{
      project_context: {
        stack: {language: $language, framework: $framework, test_runner: $test_runner},
        has_ui: $has_ui,
        design_system_exists: ($design_system_md | length > 0),
        design_system_md: $design_system_md,
        okf_bundle_valid: true
      },
      concepts_by_category: $concepts_by_cat,
      decisions_accepted: $decisions_accepted,
      known_problems_open: $problems_open,
      db_counts: {concepts: $db_concepts, decisions: $db_decisions, preferences: $db_prefs},
      project_yaml_mtime: $yaml_mtime,
      generated_at: $generated_at
    }' | tee "$CACHE_FILE"
}

# Main
if ! read_cache_if_valid; then
    build_cache
fi