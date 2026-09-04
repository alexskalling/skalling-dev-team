#!/usr/bin/env bash
# Renderiza un agente desde agents-base: expande snippets y elimina copias legacy.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT="$(dirname "$SCRIPT_DIR")"
AGENT_FILE="${1:-}"

[ -f "$AGENT_FILE" ] || { echo "ERROR: agente no encontrado: $AGENT_FILE" >&2; exit 1; }

resolved_content="$(cat "$AGENT_FILE")"
depth=0
while [[ "$resolved_content" =~ @include-snippet[[:space:]]+([a-z-]+) ]]; do
  snippet_name="${BASH_REMATCH[1]}"
  snippet_path="$ROOT/templates/agents/snippets/${snippet_name}.md"
  if [ -f "$snippet_path" ]; then
    snippet_body="$(cat "$snippet_path")"
    resolved_content="${resolved_content//<!-- @include-snippet $snippet_name -->/$snippet_body}"
  else
    echo "WARN: snippet no encontrado: $snippet_name" >&2
    resolved_content="${resolved_content//<!-- @include-snippet $snippet_name -->/}"
  fi
  depth=$((depth + 1))
  if [ "$depth" -gt 64 ]; then
    echo "ERROR: ciclo de snippets en $(basename "$AGENT_FILE")" >&2
    exit 1
  fi
done

printf '%s\n' "$resolved_content" | awk '
  /<!-- BEGIN LEGACY-SNIPPET-COPY -->/ { skip=1; next }
  /<!-- END LEGACY-SNIPPET-COPY -->/ { skip=0; next }
  !skip { print }
'
