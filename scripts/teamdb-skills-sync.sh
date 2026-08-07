#!/usr/bin/env bash
# teamdb-skills-sync.sh — Puebla el INDICE de skills en la DB.
# El contenido de las skills NO se toca: vive en archivos SKILL.md. Acá se
# registra solo la ficha (name/description/version/source/load_path) en:
#   - global:      skills_active      (desde $AGENTS_SKILLS_DIR y $OPENCODE_DIR/skills)
#   - proyecto:    skills_registry    (desde .opencode/skills y skills-lock.json)
# Idempotente: upsert por name/skill_name. Uso: teamdb-skills-sync.sh [proyecto]
# Lock file (se aplica al final, después de parsing $PROJECT)
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SKALLING_ROOT_DIR="$(dirname "$SCRIPT_DIR")"
export SKALLING_ROOT="$SKALLING_ROOT_DIR"

if [ -f "$SCRIPT_DIR/lib-teamdb.sh" ]; then
  # shellcheck disable=SC1091
  source "$SCRIPT_DIR/lib-teamdb.sh"
elif [ -f "$SCRIPT_DIR/lib/lib-teamdb.sh" ]; then
  # shellcheck disable=SC1091
  source "$SCRIPT_DIR/lib/lib-teamdb.sh"
else
  echo "ERROR: lib-teamdb.sh no encontrado" >&2
  exit 1
fi

PROJECT="${1:-}"
# Lock file para evitar race conditions entre agentes
LOCK_DIR="$PROJECT/.opencode/context"
LOCK_FILE="$LOCK_DIR/team.lock"
mkdir -p "$LOCK_DIR" 2>/dev/null || true
if command -v flock >/dev/null 2>&1; then
  exec 9>"$LOCK_FILE" 2>/dev/null || true
  flock -w 10 9 || { echo "ERROR: no se pudo obtener lock en $LOCK_FILE" >&2; exit 1; }
fi
trap 'exec 9>&- 2>/dev/null' EXIT

AGENTS_SKILLS_DIR="${AGENTS_SKILLS_DIR:-$HOME/.agents/skills}"
OPENCODE_SKILLS_DIR="${OPENCODE_SKILLS_DIR:-$(dirname "$(teamdb_global_path)")/skills}"

# extract_meta <SKILL.md> — imprime "name<TAB>description<TAB>version" desde el frontmatter
extract_meta() {
  local md="$1"
  [ -f "$md" ] || return 1
  python3 - "$md" <<'PY'
import json, re, sys
md = open(sys.argv[1], encoding='utf-8').read()
m = re.match(r'^---\s*\n(.*?)\n---', md, re.S)
meta = {'name': '', 'description': '', 'version': ''}
if m:
    for line in m.group(1).splitlines():
        line = line.strip()
        if ':' in line and not line.startswith('#'):
            k, _, v = line.partition(':')
            meta[k.strip()] = v.strip().strip('"\'')
print('%s\t%s\t%s' % (meta.get('name'), meta.get('description'), meta.get('version')))
PY
}

# sync_global: skills_active en el team.db global
sync_global() {
  local db
  db="$(teamdb_init_global)" || return 1
  local dir
  for dir in "$AGENTS_SKILLS_DIR" "$OPENCODE_SKILLS_DIR"; do
    [ -d "$dir" ] || continue
    local skill_md
    for skill_md in "$dir"/*/SKILL.md; do
      [ -f "$skill_md" ] || continue
      local meta
      meta="$(extract_meta "$skill_md")"
      local name desc ver
      name="$(echo "$meta" | cut -f1)"; desc="$(echo "$meta" | cut -f2)"; ver="$(echo "$meta" | cut -f3)"
      [ -n "$name" ] || name="$(basename "$(dirname "$skill_md")")"
      teamdb_write_global \
        "INSERT INTO skills_active(skill_name, description, version, source, load_path) VALUES(?,?,?,?,?) ON CONFLICT(skill_name) DO UPDATE SET description=excluded.description, version=excluded.version, source=excluded.source, load_path=excluded.load_path" \
        "$name" "$desc" "$ver" "filesystem" "$skill_md" >/dev/null 2>&1 || return 1
    done
  done
}

# sync_project: skills_registry en el team.db del proyecto
sync_project() {
  local project="$1"
  local db; db="$(teamdb_project_path "$project")"
  if [ ! -f "$db" ]; then
    echo "[ERROR] DB de proyecto no existe: $db (correr teamdb-init.sh $project)" >&2
    return 1
  fi
  local has_table
  has_table="$(sqlite3 "$db" "SELECT COUNT(*) FROM sqlite_master WHERE type='table' AND name='skills_registry'" 2>/dev/null)"
  if [ "$has_table" != "1" ]; then
    echo "[ERROR] skills_registry ausente en $db (correr teamdb-init.sh $project)" >&2
    return 1
  fi

  # .opencode/skills/<name>/SKILL.md
  local skills_dir="$project/.opencode/skills"
  if [ -d "$skills_dir" ]; then
    local skill_md
    for skill_md in "$skills_dir"/*/SKILL.md; do
      [ -f "$skill_md" ] || continue
      local meta name desc ver
      meta="$(extract_meta "$skill_md")"
      name="$(echo "$meta" | cut -f1)"; desc="$(echo "$meta" | cut -f2)"; ver="$(echo "$meta" | cut -f3)"
      [ -n "$name" ] || name="$(basename "$(dirname "$skill_md")")"
      teamdb_write_project "$db" \
        "INSERT INTO skills_registry(name, description, version, source, load_path) VALUES(?,?,?,?,?) ON CONFLICT(name) DO UPDATE SET description=excluded.description, version=excluded.version, source=excluded.source, load_path=excluded.load_path" \
        "$name" "$desc" "$ver" "project" "$skill_md" >/dev/null 2>&1 || return 1
    done
  fi

  # skills-lock.json: skills lockeadas (puede no haber SKILL.md local)
  local lock="$project/skills-lock.json"
  if [ -f "$lock" ]; then
    local entry
    while IFS= read -r entry; do
      [ -n "$entry" ] || continue
      local name src path
      name="$(echo "$entry" | cut -f1)"; src="$(echo "$entry" | cut -f2)"; path="$(echo "$entry" | cut -f3)"
      local desc=""
      local local_md="$project/$path"
      if [ -f "$local_md" ]; then
        desc="$(extract_meta "$local_md" | cut -f2)"
      fi
      teamdb_write_project "$db" \
        "INSERT INTO skills_registry(name, description, source, load_path) VALUES(?, NULLIF(?,''), ?, ?) ON CONFLICT(name) DO UPDATE SET description=COALESCE(NULLIF(?, ''), description), source=excluded.source, load_path=excluded.load_path" \
        "$name" "$desc" "$src" "$path" "$desc" >/dev/null 2>&1 || return 1
    done < <(python3 - "$lock" <<'PY'
import json, sys
data = json.load(open(sys.argv[1]))
for name, info in data.get('skills', {}).items():
    print('%s\t%s\t%s' % (name, info.get('source', ''), info.get('skillPath', '')))
PY
)
  fi
}

sync_global
if [ -n "$PROJECT" ]; then
  sync_project "$PROJECT"
fi
echo "skills registry sync: ok (global +${PROJECT:+ proyecto $PROJECT})"
