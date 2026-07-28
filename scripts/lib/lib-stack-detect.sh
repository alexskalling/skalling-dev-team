# lib-stack-detect.sh — Parser de stack-detectors.yaml + skills-by-stack.yaml.
#
# Lee los data files y aplica los detectores contra el PROJECT_DIR.
# No usa eval ni associative arrays (compatible bash 3.2).
#
# Fuente de verdad: data/stack-detectors.yaml
# Output: variables detected_<key> en el scope del caller.

# ──────────────────────────────────────────────────────────────────────────────
# DETECCIÓN DATA-DRIVEN
# ──────────────────────────────────────────────────────────────────────────────

# Nombres de las variables detectadas (bash 3 compatible)
SKALLING_DETECTED_KEYS="language runtime framework test_runner package_manager linter formatter has_ui description"

# Inicializa todas las variables detected_* como vacías.
skalling_init_detected() {
    local key
    for key in $SKALLING_DETECTED_KEYS; do
        eval "skalling_detected_${key}=\"\""
    done
    skalling_detected_has_ui="false"
}

# Setter con sanitización (no usar eval directo con contenido externo).
# Sanitiza: rechaza caracteres que podrían romper eval (; & $ ` etc.)
skalling_set_detected() {
    local key="$1" value="$2"
    # Sanitizar: solo permitir alfanuméricos, guion, guion bajo, punto, slash, dos puntos
    if [[ ! "$value" =~ ^[a-zA-Z0-9._:/+-]*$ ]]; then
        # Si tiene caracteres raros, sanitizar agresivamente
        value="$(printf '%s' "$value" | tr -cd 'a-zA-Z0-9._:/+-' )"
    fi
    eval "skalling_detected_${key}=\"\${value}\""
}

skalling_get_detected() {
    local key="$1"
    eval "printf '%s' \"\${skalling_detected_${key}:-}\""
}

# ──────────────────────────────────────────────────────────────────────────────
# PARSER DE YAML (minimalista — solo lo que necesitamos)
# ──────────────────────────────────────────────────────────────────────────────

# Parsea el bloque de un detector específico desde stack-detectors.yaml.
# Output: líneas "KEY=VALUE" que se pueden evaluar seguro.
skalling_parse_yaml_block() {
    local yaml_file="$1"
    local target_id="$2"

    awk -v target="$target_id" '
        BEGIN { in_block=0; current_id="" }
        /^detectors:/ { next }
        /^  - id:/ {
            # Extraer id de la línea: "- id: typescript"
            # Usando split() (POSIX) en vez de match() con array (GNU)
            n=split($0, parts, ":")
            current_id=parts[2]
            gsub(/^[ \t]+/, "", current_id)
            gsub(/[ \t]+$/, "", current_id)
            if (current_id == target) {
                in_block=1
                print "BLOCK_START=" target
                next
            } else {
                in_block=0
                next
            }
        }
        in_block && /^  - / && !/^    - / {
            in_block=0
            next
        }
        in_block {
            sub(/^    /, "")
            print
        }
    ' "$yaml_file"
}

# Extrae lista de "files:" desde un bloque parseado.
# Output: un file por línea.
skalling_extract_files() {
    local block="$1"
    echo "$block" | awk '
        /^files:/ {
            in_files=1
            if ($0 ~ /files:[[:space:]]*\[/) {
                # Extraer contenido del array inline [...]
                inline=$0
                sub(/.*\[/, "", inline)
                sub(/\].*/, "", inline)
                n=split(inline, parts, ",")
                for (i=1; i<=n; i++) {
                    gsub(/[ \047"]/, "", parts[i])
                    if (parts[i] != "") print parts[i]
                }
                in_files=0
                next
            }
            next
        }
        /^files_glob:/ {
            in_files=1
            if ($0 ~ /files_glob:[[:space:]]*\[/) {
                inline=$0
                sub(/.*\[/, "", inline)
                sub(/\].*/, "", inline)
                n=split(inline, parts, ",")
                for (i=1; i<=n; i++) {
                    gsub(/[ \047"]/, "", parts[i])
                    if (parts[i] != "") print parts[i]
                }
                in_files=0
                next
            }
            next
        }
        in_files && /^  - / {
            line=$0
            sub(/^  - /, "", line)
            print line
            next
        }
        in_files && /^[a-z]/ { in_files=0 }
    '
}

# Extrae pares pattern:value de una sección (framework, test_runner, package_manager).
# Output: alterna líneas PATTERN= y VALUE= (o DEFAULT=).
skalling_extract_section() {
    local block="$1"
    local section="$2"
    echo "$block" | awk -v section="$section" '
        BEGIN { in_section=0; current_pattern="" }
        $0 ~ ("^"section":$") { in_section=1; next }
        in_section && /^[a-z]/ && !($0 ~ ("^"section":$")) { in_section=0 }
        in_section && /^  - pattern:/ {
            # Extraer pattern (entre comillas simples)
            line=$0
            sub(/^  - pattern:[[:space:]]*/, "", line)
            gsub(/^[\047"]/, "", line)
            gsub(/[\047"]$/, "", line)
            current_pattern=line
            print "PATTERN=" line
            next
        }
        in_section && /^    value:/ {
            line=$0
            sub(/^    value:[[:space:]]*/, "", line)
            print "VALUE=" line
            next
        }
        in_section && /^  - default:/ {
            line=$0
            sub(/^  - default:[[:space:]]*/, "", line)
            print "DEFAULT=" line
            next
        }
        in_section && /^  - lockfile:/ {
            line=$0
            sub(/^  - lockfile:[[:space:]]*/, "", line)
            print "LOCKFILE=" line
            next
        }
    '
}

# ──────────────────────────────────────────────────────────────────────────────
# DETECCIÓN PRINCIPAL
# ──────────────────────────────────────────────────────────────────────────────

skalling_detect_from_yaml() {
    local yaml_file="$1"
    local project_dir="$2"

    [[ ! -f "$yaml_file" ]] && return 1

    # Listar todos los detector IDs en orden usando split() (POSIX)
    local detector_ids
    detector_ids="$(awk '
        /^  - id:/ {
            line=$0
            sub(/^  - id:[[:space:]]*/, "", line)
            print line
        }
    ' "$yaml_file")"

    local matched_id=""
    for det_id in $detector_ids; do
        local block
        block="$(skalling_parse_yaml_block "$yaml_file" "$det_id")"
        [[ -z "$block" ]] && continue

        # Verificar si algún archivo del detector existe en project_dir
        local files
        files="$(skalling_extract_files "$block")"
        local matched=false
        while IFS= read -r f; do
            [[ -z "$f" ]] && continue
            if [[ -f "$project_dir/$f" ]]; then
                matched=true
                break
            fi
            if compgen -G "$project_dir/$f" >/dev/null 2>&1; then
                local glob_match
                glob_match="$(compgen -G "$project_dir/$f" 2>/dev/null | head -1)"
                if [[ -n "$glob_match" && -e "$glob_match" ]]; then
                    matched=true
                    break
                fi
            fi
        done <<< "$files"

        if [[ "$matched" == true ]]; then
            matched_id="$det_id"

            # Extraer valores básicos del bloque
            local language runtime requires_ts
            language="$(echo "$block" | awk '/^language:/ { print $2; exit }')"
            runtime="$(echo "$block" | awk '/^runtime:/ { print $2; exit }')"
            requires_ts="$(echo "$block" | awk '/^requires_tsconfig:/ { print $2; exit }')"

            if [[ "$requires_ts" == "true" ]]; then
                if [[ -f "$project_dir/tsconfig.json" ]]; then
                    skalling_set_detected language "typescript"
                else
                    skalling_set_detected language "javascript"
                fi
            elif [[ -n "$language" ]]; then
                skalling_set_detected language "$language"
            fi
            [[ -n "$runtime" ]] && skalling_set_detected runtime "$runtime"

            # Framework detection
            local fw_patterns
            fw_patterns="$(skalling_extract_section "$block" framework)"
            if [[ -n "$fw_patterns" ]]; then
                local current_pattern="" fw_value=""
                local line
                while IFS= read -r line; do
                    if [[ "$line" =~ ^PATTERN= ]]; then
                        current_pattern="${line#PATTERN=}"
                    elif [[ "$line" =~ ^VALUE= ]]; then
                        local val="${line#VALUE=}"
                        # Buscar pattern en los archivos del proyecto
                        local check_files="package.json pyproject.toml requirements.txt Cargo.toml go.mod pom.xml build.gradle build.gradle.kts mix.exs pubspec.yaml"
                        for cf in $check_files; do
                            [[ ! -f "$project_dir/$cf" ]] && continue
                            if grep -qE "$current_pattern" "$project_dir/$cf" 2>/dev/null; then
                                fw_value="$val"
                                break 2
                            fi
                        done
                        current_pattern=""
                    fi
                done <<< "$fw_patterns"
                [[ -n "$fw_value" ]] && skalling_set_detected framework "$fw_value"
            fi

            # Test runner detection
            local tr_patterns
            tr_patterns="$(skalling_extract_section "$block" test_runner)"
            if [[ -n "$tr_patterns" ]]; then
                local current_pattern="" tr_value="" tr_default=""
                local line
                while IFS= read -r line; do
                    if [[ "$line" =~ ^PATTERN= ]]; then
                        current_pattern="${line#PATTERN=}"
                    elif [[ "$line" =~ ^VALUE= ]]; then
                        local val="${line#VALUE=}"
                        local check_files="package.json pyproject.toml requirements.txt Cargo.toml go.mod pom.xml build.gradle build.gradle.kts mix.exs pubspec.yaml"
                        for cf in $check_files; do
                            [[ ! -f "$project_dir/$cf" ]] && continue
                            if grep -qE "$current_pattern" "$project_dir/$cf" 2>/dev/null; then
                                tr_value="$val"
                                break 2
                            fi
                        done
                        current_pattern=""
                    elif [[ "$line" =~ ^DEFAULT= ]]; then
                        tr_default="${line#DEFAULT=}"
                    fi
                done <<< "$tr_patterns"
                [[ -z "$tr_value" && -n "$tr_default" ]] && tr_value="$tr_default"
                [[ -n "$tr_value" ]] && skalling_set_detected test_runner "$tr_value"
            fi

            # Package manager detection
            local pm_patterns
            pm_patterns="$(skalling_extract_section "$block" package_manager)"
            if [[ -n "$pm_patterns" ]]; then
                local current_lockfile="" pm_value="" pm_default=""
                local line
                while IFS= read -r line; do
                    if [[ "$line" =~ ^LOCKFILE= ]]; then
                        current_lockfile="${line#LOCKFILE=}"
                    elif [[ "$line" =~ ^VALUE= ]]; then
                        local val="${line#VALUE=}"
                        if [[ -f "$project_dir/$current_lockfile" ]]; then
                            pm_value="$val"
                            break
                        fi
                        current_lockfile=""
                    elif [[ "$line" =~ ^DEFAULT= ]]; then
                        pm_default="${line#DEFAULT=}"
                    fi
                done <<< "$pm_patterns"
                [[ -z "$pm_value" && -n "$pm_default" ]] && pm_value="$pm_default"
                [[ -n "$pm_value" ]] && skalling_set_detected package_manager "$pm_value"
            fi

            break
        fi
    done

    # has_ui heurística
    local fw
    fw="$(skalling_get_detected framework)"
    case "$fw" in
        react|vue|svelte|nextjs|astro|nuxt|flutter|react-native|swiftui)
            skalling_set_detected has_ui "true"
            ;;
    esac

    # Descripción del proyecto (de README.md)
    if [[ -f "$project_dir/README.md" ]]; then
        local desc
        desc="$(head -20 "$project_dir/README.md" 2>/dev/null | { grep -v "^#" || true; } | head -3 | tr '\n' ' ' | sed 's/  */ /g' | cut -c 1-200)"
        skalling_set_detected description "$desc"
    fi
}

# ──────────────────────────────────────────────────────────────────────────────
# SKILLS-BY-STACK LOOKUP
# ──────────────────────────────────────────────────────────────────────────────

skalling_recommended_skills_for_stack() {
    local yaml_file="$1"
    local stack_key="$2"

    [[ ! -f "$yaml_file" ]] && return 1

    awk -v key="$stack_key" '
        BEGIN { in_section=0; current="" }
        /^[a-z_-]+:$/ {
            current=tolower($1)
            sub(/:$/, "", current)
            in_section = (current == key)
            next
        }
        in_section && /^custom:/ { exit }
        in_section && /^[a-z]/ && !/^[a-z_-]+:$/ { in_section=0 }
        in_section && /^  - name:/ {
            line=$0
            sub(/^  - name:[[:space:]]*/, "", line)
            # split en lugar de match con array (POSIX-only)
            n=split(line, parts, " ")
            print parts[1]
        }
    ' "$yaml_file"
}

skalling_core_skills() {
    local yaml_file="$1"

    [[ ! -f "$yaml_file" ]] && return 1

    awk '
        /^core:/ { in_core=1; next }
        in_core && /^custom:/ { exit }
        in_core && /^[a-z]/ && !/^core:/ { in_core=0 }
        in_core && /^  - name:/ {
            line=$0
            sub(/^  - name:[[:space:]]*/, "", line)
            n=split(line, parts, " ")
            print parts[1]
            next
        }
    ' "$yaml_file"
}

# Devuelve la lista de skills marcadas como stack-specific (las que NO son core).
skalling_stack_specific_skills() {
    local yaml_file="$1"

    [[ ! -f "$yaml_file" ]] && return 1

    awk '
        BEGIN { in_core=0; in_top_level=0 }
        /^detectors:/ { exit }
        /^core:/ { in_core=1; next }
        in_core && /^[a-z]/ && !/^core:/ { in_core=0 }
        in_core && /^  - name:/ { next }
        /^[a-z_-]+:$/ {
            current=tolower($1)
            sub(/:$/, "", current)
            in_top_level=1
            next
        }
        in_top_level && /^custom:/ { exit }
        in_top_level && /^[a-z]/ && !/^[a-z_-]+:$/ { in_top_level=0 }
        in_top_level && /^  - name:/ {
            line=$0
            sub(/^  - name:[[:space:]]*/, "", line)
            n=split(line, parts, " ")
            print parts[1]
        }
    ' "$yaml_file"
}


