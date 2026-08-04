# Design: Drift detection para specs archivadas

> **Status**: Draft
> **Feature**: `skalling-drift-detection`
> **Basado en**: `proposal.md` + `specs/01-script-principal.md` + `specs/02-formato-de-claims.md` + `specs/03-tests-y-doctor.md`
> **Decisiones**: con rationale y alternativas consideradas

---

## Arquitectura

Drift detection es un CLI Bash de un solo archivo que contrastas los claims declarados en `## Verificación` de cada spec archivada contra el estado actual del repositorio. El script es **de solo lectura**: no modifica nada, no escribe en logs, no toca git. Su único efecto observable es exit code y reporte por stdout/stderr.

El diseño se organiza en 3 capas internas dentro de `scripts/skalling-drift.sh`:

```
┌─────────────────────────────────────────────────────────────────┐
│ main()                                                          │
│   1. Validar argv y resolver rutas                              │
│   2. Listar specs/*.md                                          │
│   3. Parsear bloques ## Verificación                            │
│   4. Verificar cada claim                                       │
│   5. Imprimir reporte y resumen                                 │
│   6. Exit code                                                  │
└─────────────────────────────────────────────────────────────────┘
              ↓                  ↓                  ↓
    ┌───────────────┐    ┌───────────────┐    ┌───────────────┐
    │  Parseo       │    │  Verificación │    │  Reporte      │
    │ ─────────────  │    │ ─────────────  │    │ ─────────────  │
    │ extraer_bloque│    │verificar_arch │    │ imprimir_linea│
    │ parsear_claim │    │contar_archivos│    │ imprimir_resu │
    │ validar_path  │    │archivo_contie │    │ activar_color │
    └───────────────┘    └───────────────┘    └───────────────┘
```

### Flujo de ejecución (happy path)

```
$ bash scripts/skalling-drift.sh .opencode/changes/archive/2026-08/memory/
   │
   ├─ argv: validar 1 arg posicional → REPO_ROOT desde BASH_SOURCE
   ├─ plan = $1; resolver a absoluto vía cd
   ├─ test: [[ -d $plan && -d $plan/specs ]]   → si falla: error accionable stderr, exit 1
   ├─ specs = $(find $plan/specs -maxdepth 1 -type f -name '*.md' | sort)
   ├─ si specs vacío → error accionable, exit 1
   │
   ├─ para cada spec en specs:
   │   ├─ estado = fuera
   │   ├─ leer línea por línea
   │   ├─ si línea == "## Verificación" y estado == fuera → estado = dentro
   │   ├─ si línea == "## "* y estado == dentro → break (fin de bloque)
   │   ├─ si estado == dentro:
   │   │     ├─ case "$line" en "- archivo:"|"- count:"|"- contiene:":
   │   │     │     └─ dispatch según prefijo a verificar_*
   │   │     └─ else (línea narrativa o bullet no reconocido): ignorar
   │   └─ fin de archivo → break
   │
   ├─ imprimir_resumen $total_aprobados $total_fallidos
   └─ exit 0 si total_fallidos == 0 y total_reconocidos > 0; else exit 1
```

---

## Decisiones Arquitectónicas (ADRs)

### ADR-001: Parser lineal por bloque (no AST, no descendente recursivo)

**Contexto**: El formato de `## Verificación` es un DSL pequeño: un solo bloque delimitado por headings nivel 2. Necesitamos extraer bullets con prefijo conocido y ejecutar su verificación.

**Decisión**: State machine lineal de 2 estados (`fuera` / `dentro`) implementado con `case` y `while IFS= read -r` en Bash.

**Rationale**:
- El bloque tiene estructura plana y delimitada por headings nivel 2; no hay anidación.
- Un parser descendente recursivo sería over-engineering para 3 prefijos conocidos.
- `case` es la forma idiomática de Bash para dispatch por prefijo, y es portable a Bash 3.2.

**Alternativas consideradas**:
- AST formal con `yacc`/`bison`: overkill para 3 patrones y trae dependencia externa.
- `awk` para procesar: perderíamos la integración natural con `find`/`grep` y complicaría el reporte.
- Embeber un mini-parser en Python: viola "Bash 3.2 portable" y agrega dependencia de runtime.

**Consecuencias**:
- (+) Simple de auditar (puede leerse de una sola pasada).
- (+) Sin dependencias externas.
- (-) Si en el futuro se agregan bloques anidados (no en scope), hay que rehacer el parser.

### ADR-002: Orden lexicográfico de specs vía `find … | sort`

**Contexto**: Las specs son archivos `.md` dentro de `specs/`. ¿En qué orden se procesan?

**Decisión**: `find "$specs_dir" -maxdepth 1 -type f -name '*.md' | sort`.

**Rationale**:
- Spec escenario 1 MUST: "leer todos los `.md` … en orden lexicográfico".
- `sort` con locale C (default en Mac y Linux coreutils) es determinístico y portable.
- `find -maxdepth 1` evita recursión accidental en subdirectorios.

**Alternativas consideradas**:
- Glob `specs/*.md` y orden natural de la shell: el orden depende de la implementación de `readdir` del FS, no portable.
- `find -print0` + `xargs -0 sort`: innecesario para nombres sin espacios (la spec excluye paths con espacios).

**Consecuencias**:
- (+) Reproducibilidad cross-platform.
- (-) Si Pau numeró los specs (`01-foo.md`, `02-bar.md`), el orden coincide — lucky accident, no dépendance.

### ADR-003: Colores condicionales a TTY (default OFF en tests)

**Contexto**: El output puede ir a una terminal humana o ser capturado por un test. La spec SHOULD 02 dice "los tests no dependen del color".

**Decisión**: Las secuencias ANSI solo se emiten si `[[ -t 1 ]] && [[ -t 2 ]]`. El helper `activar_color` setea `MODO_COLOR=1` cuando TTY, `=0` cuando pipe/redirect.

```bash
activar_color() {
  if [[ -t 1 ]] && [[ -t 2 ]]; then
    MODO_COLOR=1
  else
    MODO_COLOR=0
  fi
}
```

Los helpers `imprimir_ok`, `imprimir_fallo`, `imprimir_resumen` consultan `MODO_COLOR` y eligen entre secuencia ANSI o literal sin color.

**Alternativas consideradas**:
- `--color=always|auto|never` estilo GNU: más amigable pero introduce parsing de flag nuevo y varianza.
- Variable de entorno `SKALLING_DRIFT_COLOR`: ortogonal al TTY check pero engrosa superficie.

**Consecuencias**:
- (+) Tests corren limpios (sin ruido ANSI en `grep`).
- (+) Usuario humano en TTY ve color sin pensar.
- (-) Si el usuario hace `| less`, el color se pierde — aceptable, es el comportamiento Unix estándar.

### ADR-004: Identificadores en español, incluidos nombres de colores

**Contexto**: R1 (constitución) exige identifiers propios en español. El repo existente usa `c_green`/`c_red`/`c_yellow`/`c_blue` en `setup.test.sh` y `setup-team-doctor.sh` — divergen del español.

**Decisión**: En `scripts/skalling-drift.sh` y `tests/skalling-drift.test.sh`, los identificadores serán estrictamente en español:
- Variables de color: `c_verde`, `c_rojo`, `c_azul`, `c_neutro`.
- Funciones: `verificar_claim`, `contar_archivos`, `archivo_contiene`, `validar_path_relativo`, `extraer_bloque_verificacion`, `imprimir_linea_resultado`, `imprimir_resumen`.
- Constantes: `total_aprobados`, `total_fallidos`, `total_reconocidos`, `MODO_COLOR`.

**Rationale**: R1 es MUST para todo código nuevo. No podemos pedirle al equipo que adopte `c_verde` retroactivamente sin migración; pero el código nuevo que escribimos nosotros puede cumplir R1 desde el día uno.

**Alternativas consideradas**:
- Mantener `c_green`/`c_red` para "consistencia": viola R1 para archivos nuevos que escribimos.
- Hacer un PR retroactivo renombrando `c_green → c_verde` en todo el repo: fuera del scope de esta feature.

**Consecuencias**:
- (+) Cumplimiento estricto de R1 desde el inicio.
- (-) Inconsistencia visual con archivos del repo (`setup.test.sh` se ve distinto). Aceptable; el cambio es backward-compatible (`grep` por nombres propios no se hace cross-file).

### ADR-005: Integración del doctor como `info`, no como `section`

**Contexto**: Spec escenario 9 dice que el doctor debe incluir "una sección o línea informativa" sobre drift detection. ¿Creamos una nueva sección con `section "Drift detection"` o agregamos una línea suelta?

**Decisión**: Una línea `info` al **final** de `check_project_install()`, condicional a que `scripts/skalling-drift.sh` exista en `$SCRIPT_DIR`.

```bash
if [[ -f "$SCRIPT_DIR/scripts/skalling-drift.sh" ]]; then
    info "Drift detection disponible: bash scripts/skalling-drift.sh <plan-archivado>"
else
    info "Drift detection NO instalado (futuro feature, ver .opencode/changes/skalling-drift-detection)"
fi
```

Esto va justo después del bloque "Changes (SDD)" en `check_project_install()`, **antes** de la posible invocación a `check_memory_health()`.

**Rationale**:
- "Informativa y no bloqueante" implica no inflar la jerarquía visual del doctor.
- `info()` ya incrementa nada (`OK_COUNT`/`WARN_COUNT`/`ERROR_COUNT` no se modifican) → exit code del doctor no cambia.
- Condicional: si el archivo no existe (instalación vieja, repo antes de este feature), no aparece como warning → no regresión.

**Alternativas consideradas**:
- Nueva función `check_drift_detection()` con su propia `section`: pesa demasiado para una línea informativa. Escala mejor cuando la feature crezca (fuera de scope de MVP).
- `warn` condicional si no existe: viola "informativa y no bloqueante".

**Consecuencias**:
- (+) Cambio mínimo a `setup-team-doctor.sh` (3 líneas).
- (+) Sin riesgo de regresión en contadores del doctor.
- (-) Si el feature crece, hay que mover la integración; esperado — el MVP lo justifica.

### ADR-006: Fixture autocontenida para tests, copiando el script

**Contexto**: Spec escenario 2 de spec 03 dice que los tests deben crear una fixture autocontenida con copia del script. ¿Cómo resolvemos `REPO_ROOT` desde dentro del script cuando el test lo invoca?

**Decisión**: El test copia `scripts/skalling-drift.sh` desde el repo real hacia `$FIXTURE/scripts/skalling-drift.sh`. Cuando el test lo invoca `bash "$FIXTURE/scripts/skalling-drift.sh"`, el `BASH_SOURCE[0]` apunta a la copia, y `REPO_ROOT` se resuelve como `$FIXTURE`. Así el script valida contra el filesystem de la fixture, no contra el repo real.

**Rationale**:
- "Spec escenario 2" MUST: "el script no debe modificar archivos versionados del repositorio" + fixture autocontenida.
- Si la fixture tiene `agents-base/Alex.md`, ese es el archivo que valida `archivo: agents-base/Alex.md`, no el del repo real.

**Alternativas consideradas**:
- Setear variable de entorno `SKALLING_DRIFT_REPO_ROOT` para override: introduce flag nuevo, pero el spec no lo exige.
- Hardcodear el path real del repo en el script: viola portabilidad y hace imposible tests aislados.

**Consecuencias**:
- (+) Test corre en sandbox completo (`mktemp -d`), no toca repo real.
- (+) Test puede manipular el fixture para forzar PASS/FAIL de cada tipo (crear/borrar archivo, renombrar, etc.).
- (-) Copy extra del script (~5KB); aceptable.

### ADR-007: Bump minor a 0.5.0 (propuesta, decisión del usuario)

**Contexto**: La versión actual es `0.4.0` (en `VERSION` y `SKALLING_VERSION`). Drift detection es una feature aditiva, backward-compatible.

**Decisión propuesta**: `0.4.0` → `0.5.0` (minor).

**Rationale**:
- SemVer: funcionalidad aditiva backward-compatible = minor (Y).
- No rompe ningún surface existente (no cambia doctor exit code, no modifica APIs).
- No es bugfix ni patch (X), no es breaking (Z).

**Alternativas**:
- 0.4.1 (patch): subestima la feature.
- 1.0.0 (major): prematuro mientras sigamos pre-1.0; Skalling está en desarrollo activo.

**Consecuencias**: CHANGELOG entra bajo `[Unreleased]` durante desarrollo, se renombra a `[0.5.0] — YYYY-MM-DD` al cerrar.

---

## Modelo de Datos (Gramática de Claims)

No hay schema persistente. La gramática de los 3 tipos de claims es el "modelo de datos" del script. Se documenta como BNF + ejemplo.

### claim_archivo

```
claim_archivo   ::= '- archivo:' WS+ ruta_relativa
ruta_relativa   ::= segmento ('/' segmento)*
segmento        ::= [a-zA-Z0-9._-]+           # sin espacios, sin '..', sin vacío
```

Ejemplo válido: `- archivo: agents-base/Alex.md`.
Ejemplo inválido: `- archivo: ../Alex.md`, `- archivo: /abs/Alex.md`, `- archivo: con espacios.md`.

### claim_count

```
claim_count     ::= '- count:' WS+ INT WS+ etiqueta WS+ 'en' WS+ ruta_directorio
INT             ::= [0-9]+
etiqueta        ::= [^[:space:]]+ (' ' [^[:space:]]+)* ' '*   # sin la secuencia ' en '
ruta_directorio ::= segmento ('/' segmento)*
```

Ejemplo válido: `- count: 8 agentes en agents-base`.
Ejemplo inválido: `- count: ocho agentes en agents-base` (INT debe ser decimal), `- count: 8 en agents-base` (etiqueta vacía), `- count: 8 agentes en con espacios` (path inválido).

### claim_contiene

```
claim_contiene  ::= '- contiene:' WS+ '"' texto '"' WS+ 'en' WS+ ruta_archivo
texto           ::= [^"]+                       # sin comillas dobles escapadas en MVP
ruta_archivo    ::= segmento ('/' segmento)*
```

Ejemplo válido: `- contiene: "SINCRONIZADO CON:" en agents-base/Alex.md`.
Ejemplo inválido: `- contiene: "" en agents-base/Alex.md` (texto vacío), `- contiene: "txt con \"comillas\"" en …` (escapes fuera de MVP).

### Estados del parser

```
fuera ── línea == "## Verificación" ──→ dentro
dentro ── línea == "## "* ──→ fuera (fin de bloque)
dentro ── EOF ──→ fin (sale del loop)

dentro + línea == "- archivo: <ruta>"  ──→ verificar_archivo
dentro + línea == "- count: <N> <et> en <dir>" ──→ verificar_count
dentro + línea == "- contiene: \"<txt>\" en <arch>" ──→ verificar_contiene
dentro + línea reconoce prefijo pero gramática rota ──→ claim_malformado (FAIL)
dentro + línea no reconoce prefijo ──→ ignorar (silencioso)
```

---

## Patrones aplicados

### POSIX first (R14 ladder)

| Peldaño | Uso en drift detection |
|---|---|
| stdlib | `find`, `grep`, `wc`, `sed`, `awk`, `[[ ]]` |
| Bash builtin | `case`, `while read`, `[[ =~ ]]` para regex simple |
| 3rd-party | **ninguna** |

`grep -Fq -- "$texto" "$archivo"` para el check `contiene` viene del peldaño 1 (POSIX). No usamos `rg`, no usamos `ag`.

### Bash 3.2 portable

- **No** `declare -A` (arrays asociativos, Bash 4+).
- **No** `mapfile`, `readarray` (Bash 4+).
- **Sí** `case` patterns con globs extendidos (3.0+).
- **Sí** `[[ "$str" =~ $regex ]]` (3.0+).
- **Sí** arrays indexados: `arr=("a" "b")`; `for x in "${arr[@]}"`.

Test que valida esto está en escenario 8 de spec 03: `bash -n scripts/skalling-drift.sh` + `grep -E 'declare -A|mapfile|readarray' scripts/skalling-drift.sh` debe ser vacío.

### Helpers en español (R1)

| Helper | Propósito |
|---|---|
| `verificar_claim` | Dispatch principal: toma 1 línea del bloque, llama al verificador específico |
| `verificar_archivo` | Implementa `archivo:` |
| `verificar_count` | Implementa `count:` |
| `verificar_contiene` | Implementa `contiene:` |
| `contar_archivos` | Cuenta archivos regulares en `-maxdepth 1` |
| `archivo_contiene` | Wrapper de `grep -Fq` con mensaje de error claro |
| `validar_path_relativo` | Rechaza vacío, `..`, absoluto, con espacios |
| `detectar_inicio_bloque` | Match exacto `## Verificación` |
| `detectar_fin_bloque` | Match prefijo `## ` |
| `extraer_bloque_verificacion` | Itera un archivo y emite líneas del bloque |
| `imprimir_linea_resultado` | Una línea PASS o FAIL con contexto |
| `imprimir_resumen` | Totales al final |
| `imprimir_error_entrada` | A stderr con prefijo claro |
| `activar_color` | Setea `MODO_COLOR` según TTY |

### Patrón de exit codes (Escenario 5 spec 01)

| Condición | Exit |
|---|---|
| Todos los claims reconocidos pasan, al menos 1 reconocido | `0` |
| Algún claim falla (PASS + FAIL mixto) | `1` |
| Cero claims reconocidos | `1` |
| Error de entrada (cualquier motivo de Escenario 6 spec 01) | `1` |

---

## Seguridad (Validación de paths)

Drift detection es solo lectura, pero igual valida paths como defensa contra specs maliciosas o errores de Pau.

### Anti-traversal

```
[[ "$ruta" == *"/.."* || "$ruta" == "../"* || "$ruta" == ".."* ]]
```

Más robusto: split por `/` y rechazar cualquier segmento exactamente igual a `..`. Implementado en `validar_path_relativo`.

### Anti-path absoluto

```
[[ "$ruta" == /* || "$ruta" == ~* ]]
```

Rechaza paths que empiecen con `/` (Unix) o `~` (home expansion). El script siempre resuelve contra `REPO_ROOT`, no contra `pwd` del invocador.

### No ejecución automática

- El doctor no llama al script — el usuario decide cuándo correrlo.
- El script no modifica specs, código, ni archivos del plan.
- No hay `eval`, no hay `source` de archivos externos, no hay network calls.

### Claims malformados son fail

Un claim con prefijo reconocido pero gramática rota (`- count: ocho en foo`, `- archivo: ` sin path) debe **fallar**, no ignorarse silenciosamente. Esto evita que un typo aparente estar verificado cuando nunca se ejecutó (spec Escenario 3 spec 02).

---

## Testing Strategy

### Estructura del archivo de tests

`tests/skalling-drift.test.sh` sigue el patrón de `tests/setup.test.sh` (helper `pass`/`fail`/`log`, contadores, `--verbose`) **sin** los comentarios descriptivos que `setup.test.sh` sí tiene (R2 ZERO comments).

```bash
#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SCRIPT="$ROOT/scripts/skalling-drift.sh"
FIXTURE="$(mktemp -d)"
trap 'rm -rf "$FIXTURE"' EXIT

PASS=0
FAIL=0
FAILED=()

c_verde='\033[32m'
c_rojo='\033[31m'
c_azul='\033[36m'
c_neutro='\033[0m'

pass() { PASS=$((PASS + 1)); printf "  ${c_verde}✓${c_reset} %s\n" "$*"; }
fail() { FAIL=$((FAIL + 1)); FAILED+=("$*"); printf "  ${c_rojo}✗${c_reset} %s\n" "$*" >&2; }
log()  { if [[ "$VERBOSE" == true ]]; then printf "    %s\n" "$*"; fi; }

VERBOSE=false
while [[ $# -gt 0 ]]; do
    case "$1" in
        --verbose|-v) VERBOSE=true; shift ;;
        *) echo "Arg desconocido: $1"; exit 1 ;;
    esac
done
```

### Fixture pattern (helper `preparar_fixture`)

```bash
preparar_fixture() {
    local plan_slug="$1"
    local plan_dir="$FIXTURE/.opencode/changes/archive/2026-08/$plan_slug"
    mkdir -p "$plan_dir/specs"
    mkdir -p "$FIXTURE/agents-base"
    mkdir -p "$FIXTURE/scripts"
    cp "$SCRIPT" "$FIXTURE/scripts/skalling-drift.sh"
}
```

El test crea `$FIXTURE/agents-base/Alex.md` con contenido conocido (incluye `SINCRONIZADO CON:`), luego escribe specs en `$FIXTURE/.opencode/changes/archive/2026-08/<plan>/specs/`, y finalmente corre:

```bash
bash "$FIXTURE/scripts/skalling-drift.sh" ".opencode/changes/archive/2026-08/$plan_slug"
```

### Cobertura por escenario de spec 03

| Escenario | Test function |
|---|---|
| Estructura del test | `test_estructura_test_existe` |
| Fixtures temporales + cleanup | `test_fixture_cleanup_con_trap` (verifica `ls $FIXTURE` post-trap) |
| PASS con 3 claims | `test_happy_path_tres_claims` |
| FAIL mixto | `test_drift_mixto` |
| `archivo:` ausente | `test_archivo_ausente` |
| `count:` con N incorrecto | `test_count_incorrecto` |
| `contiene:` archivo sin texto | `test_contiene_sin_texto` |
| `contiene:` archivo ausente | `test_contiene_archivo_ausente` |
| Errores de entrada (7 casos) | un test por caso |
| Límites del bloque (narrative + headings variantes) | `test_bloque_limites` |
| Portabilidad B3.2 | `test_bash_3_2_portable` |
| Integración doctor | `test_doctor_info_drift_detection` |

Total estimado: ~22 funciones de test, ~60-80 asserts. Razonable para un MVP.

### Assertions (helpers específicos)

```bash
afirmar_exit_code() {
    set +e
    OUTPUT="$(bash "$FIXTURE/scripts/skalling-drift.sh" "$1" 2>&1)"
    STATUS=$?
    set -e
    if [[ "$STATUS" -eq "$2" ]]; then
        pass "exit $2: $3"
    else
        fail "exit esperado $2, obtuvo $STATUS: $3"
        log "Output: $OUTPUT"
    fi
}

afirmar_contiene() {
    if [[ "$OUTPUT" == *"$1"* ]]; then
        pass "$2"
    else
        fail "$2 — no contiene '$1'"
        log "Output: $OUTPUT"
    fi
}
```

Patrón compatible con `set -euo pipefail` (escenario 6 spec 03 MUST 6: capturar status no cero usando `set +e`/`set -e`).

---

## Riesgos conocidos

1. **`count` cuenta archivos ocultos**: el spec dice "filas regulares directamente en el directorio" sin filtro, pero specs podrían sorprenderse si un `.DS_Store` o `.gitkeep` se cuenta. Mitigación documentada en ADR; si Pau quiere excluir, agregamos `-not -name '.*'` en `contar_archivos`. Por ahora: comportamiento = literal spec.

2. **Variantes tipográficas del heading**: `## Verificacion` (sin tilde), `### Verificación`, `## verificación` → todos ignorados. Si Pau tilda mal el heading, el script no emite ningún error, simplemente no verifica nada → exit 1 silencioso. Mitigación: tests cubren variantes; documentado en `command/skalling-doctor.md` como pre-requisito humano.

3. **Fixture no limpia el repo real si falla**: la copia del script + `cp` está dentro de `$FIXTURE`. El `trap` es la línea 8 del test, antes de cualquier operación. Riesgo bajo, pero se valida en `test_fixture_cleanup_con_trap` que verifica el directorio NO existe post-test.

4. **Compatibilidad con shebangs distintos en `bash`**: el script usa `#!/usr/bin/env bash` para portabilidad. En sistemas donde `env` no está en `/usr/bin` (Windows nativo sin Git Bash), esto falla — pero esos sistemas no corren Bash scripts. Aceptable.

5. **Diferencia de salida entre TTY y pipe**: con pipe, no hay color. Si un usuario redirige `> archivo.txt`, perderá color. Esperado, comportamiento Unix.

---

## Out of design (explícitamente NO incluido)

Reafirmamos los out-of-scope del `proposal.md` desde el ángulo técnico:

- **Parser YAML / JSON / multi-línea**: claims multi-línea y frontmatter YAML están descartados — la gramática es de una línea por bullet.
- **Ejecución automática desde el doctor**: el doctor solo *informa*; no escanea planes, no cambia exit code.
- **Auto-corrección o sugerencia de fix**: el script no dice "actualizá la spec a X". El usuario debe hacerlo manualmente.
- **CI / git hooks**: no instalamos nada en `.github/` ni en hooks. La ejecución es manual y local.
- **Validación de parsers por spec**: no descargamos `ajv`, `check-jsonschema`, ni nada externo. La validación es por `bash -n` + `grep` de antipatrones.
- **Benchmark de performance**: no medimos cuántos claims por segundo procesamos. Si Pau tiene planes con 1000+ claims, evaluamos en una feature posterior.
- **Soporte para paths con espacios**: spec MUST regla 5 los excluye. No los soportamos.
- **Globbing en paths (`*.md` como argumento)**: no. El argumento es siempre un directorio de plan.
- **Regex en `contiene`**: solo literal case-sensitive. `grep -Fq` es canónico.
- **Recursión en `count`**: solo `-maxdepth 1`. Subdirectorios no se cuentan.
- **Versión 1.0.0 / API estable**: seguimos pre-1.0; SemVer surface puede romperse en minor.

---

## Resumen de identificadores claves

| Categoría | Español |
|---|---|
| Script principal | `scripts/skalling-drift.sh` |
| Script de tests | `tests/skalling-drift.test.sh` |
| Versión propuesta | `0.5.0` |
| Comandos slash | ninguno (es una herramienta CLI, no un comando slash) |
| Directorios afectados | `scripts/`, `tests/`, `setup-team-doctor.sh`, `command/skalling-doctor.md`, `VERSION`, `CHANGELOG.md` |
| Sin cambios en | `agents-base/`, `skills/`, `templates/`, `data/`, `constitucion/` (no se agregan reglas nuevas) |
