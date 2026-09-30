#!/usr/bin/env bash
# A healthy fixture includes real skills, registry and a recorded local runtime.
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
GLOBAL="${1:?}"
PROJECT="${2:?}"
git -C "$PROJECT" init -q
python3 "$ROOT/scripts/skalling_skills.py" repair --root "$ROOT" --target "$GLOBAL" >/dev/null
SKALLING_OPENCODE_DIR="$GLOBAL" AGENTS_SKILLS_DIR="$GLOBAL/personal" bash "$ROOT/setup.sh" --target "$PROJECT" </dev/null >/dev/null
mkdir -p "$PROJECT/src"
printf '%s\n' '# Fixture service' 'A service used to validate doctor diagnostics with initialized context.' > "$PROJECT/README.md"
printf '%s\n' 'def ready(): return True' > "$PROJECT/src/main.py"
cp "$ROOT/templates/project.yaml.template" "$PROJECT/.opencode/project.yaml"
python3 "$ROOT/scripts/skalling-bootstrap-context.py" --project "$PROJECT" --codegraph unavailable >/dev/null
