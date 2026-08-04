# Design: Spec ↔ Memory link — trazabilidad de concept docs a planes archivados

> **Status**: Draft
> **Feature**: `spec-memory-link`
> **Basado en**: `proposal.md` + `specs/01-deteccion-concept-docs.md` + `specs/02-archivado-con-links.md` + `specs/03-tests-y-doctor.md`
> **Decisiones**: con rationale y alternativas consideradas

---

## Arquitectura

`spec-memory-link` es un CLI Bash de un solo archivo (`scripts/spec-memory-link.sh`) que opera en dos fases bien diferenciadas dentro del mismo script:

1. **Detección** (lectura pura, sin side-effects): escanea los archivos escaneables de un plan (`proposal.md`, `design.md`, `tasks.md`, `specs/*.md`) y emite los concept docs únicos afectados.
2. **Aplicación** (escritura puntual, idempotente): recibe la lista del detector + el path final del plan archivado, y agrega un footer `## Spec original` a cada concept doc que NO lo tenga aún.

```
┌──────────────────────────────────────────────────────────────────┐
│ main()                                                           │
│   1. Validar argv (directorio-origen + directorio-destino)       │
│   2. Resolver RAIZ_REPOSITORIO desde BASH_SOURCE                 │
│   3. detectar_concept_docs "$DIR_ORIGEN"                         │
│   4. Para cada match válido:                                     │
│      ├─ validar_path_concept (existe, regex ok, no traversal)    │
│      ├─ if tiene ## Spec original → preservar (idempotencia)    │
│      └─ else → calcular_path_relativo + aplicar_footer          │
│   5. Imprimir resumen consolidado                                │
│   6. Exit code                                                    │
└──────────────────────────────────────────────────────────────────┘
              │                          │
              ▼                          ▼
    ┌────────────────────┐    ┌────────────────────────┐
    │  Detección         │    │  Aplicación            │
    │ ────────────────── │    │ ────────────────────── │
    │detectar_concept_   │    │aplicar_footer_         │
    │  docs              │    │  a_concept_doc         │
    │extraer_matches     │    │calcular_path_relativo  │
    │validar_path_concept│    │validar_footer_existente│
    │validar_argv        │    │validar_escribible      │
    │                    │    │imprimir_resumen        │
    └────────────────────┘    └────────────────────────┘
```

### Flujo de ejecución (happy path)

```
$ bash scripts/spec-memory-link.sh \
    .opencode/changes/spec-memory-link \
    .opencode/changes/archive/2026-08/spec-memory-link
   │
   ├─ argv: validar 2 args posicionales → REPO_ROOT desde BASH_SOURCE
   ├─ validar_argv:
   │   ├─ $# -eq 2                       → si no, error accionable stderr, exit 2
   │   ├─ [[ -d "$DIR_ORIGEN" ]]         → si no, error accionable stderr, exit 2
   │   └─ detectar_archivos_escaneables: al menos uno de proposal/design/tasks o specs/*.md
   │
   ├─ matches = $(detectar_concept_docs "$DIR_ORIGEN")
   │   ├─ para proposal.md, design.md, tasks.md (los que existan):
   │   │     └─ extraer_matches <archivo>  → grep -E con regex
   │   ├─ para cada *.md en specs/ (orden lexicográfico):
   │   │     └─ extraer_matches <archivo>
   │   ├─ concatenar todos los matches
   │   ├─ filtrar con sed (rechaza '..', espacios, '.md' vacío)
   │   ├─ sort -u (dedup)
   │   └─ validar_path_concept para cada uno: si no existe → advertencia stderr, descartar
   │
   ├─ si matches vacío → mensaje informativo stdout + exit 0 (no hubo trabajo pero tampoco error)
   │
   ├─ para cada concept_doc en matches:
   │   ├─ destino_relativo = calcular_path_relativo "$DIR_DESTINO"  → "../../changes/archive/<YYYY-MM>/<slug>/"
   │   ├─ if validar_footer_existente "$concept_doc":
   │   │     └─ stdout: "preservado: <concept_doc> (ya enlazado)"
   │   ├─ elif ! validar_escribible "$concept_doc":
   │   │     └─ stdout: "error: no se puede escribir <concept_doc>"
   │   ├─ elif tamaño cero:
   │   │     └─ stdout: "error: <concept_doc> está vacío"
   │   └─ else:
   │         ├─ bloque = printf con el footer
   │         ├─ escritura atómica: tmp=$(mktemp) + cat >>tmp + mv tmp destino
   │         └─ stdout: "aplicado: <concept_doc>"
   │
   ├─ imprimir_resumen (aplicados N, preservados M, errores K)
   └─ exit code:
         - 0 si al menos 1 aplicado O preservado (éxito parcial)
         - 1 si matches vacío (no hubo candidatos)
         - 2 si error de argv
         - 1 si matches tuvo candidatos pero TODOS fallaron
```

---

## Decisiones Arquitectónicas (ADRs)

### ADR-001: Single-file CLI con dos fases lógicas (detectar + aplicar)

**Contexto**: Spec MUST 02 (spec 01) dice que "ambos sub-módulos MUST vivir en el mismo script en el MVP; la separación es lógica, no física". La separación es por claridad mental, no por modularidad física.

**Decisión**: `scripts/spec-memory-link.sh` contiene ambos sub-módulos en el mismo archivo, separados por comentarios de sección (header visual `# ─── DETECCION ───` y `# ─── APLICACION ───`). Tests pueden invocar la lógica de aplicación con una lista hardcoded vía un sub-comando interno `--solo-aplicar <concept_doc> <destino>` (ver ADR-007).

**Rationale**:
- Simplicidad de distribución: un solo archivo a invocar, un solo punto de permisos.
- MVP no necesita aún modularidad física; refactorizar después si crece.

**Alternativas consideradas**:
- Dos scripts separados (`spec-memory-detect.sh` + `spec-memory-apply.sh`): doble superficie a mantener, doble permisos, doble bit ejecutable.
- Library sourceable (`lib-spec-memory.sh`): overhead para dos funciones chicas; Pau no necesita sourcearlo.

**Consecuencias**:
- (+) Un solo binario a deployar.
- (+) Tests pueden testear detector y aplicador por separado sin reimplementar.
- (-) Si crece, hay que refactorizar a library.

### ADR-002: Regex `\.opencode/context/concept/[A-Za-z0-9._-]+\.md` como fuente única de verdad

**Contexto**: Spec 01 escenario 2 fija el regex exacto: `\.opencode/context/concept/[A-Za-z0-9._-]+\.md`. Cualquier otra heurística queda fuera de scope (spec 01 out-of-spec: "Cualquier heurística que escape al regex declarado").

**Decisión**: El detector usa exclusivamente `grep -E` con ese regex. Filtrado adicional con `sed`/`grep` para rechazar:
- segmentos `..` (traversal): rechaza con `grep -F '..'` → si contiene `..`, drop.
- espacios: rechaza con `grep -v ' '`.
- nombre de archivo vacío (`/.md`): rechaza con `grep -v '/\.md$'`.

**Rationale**:
- Spec MUST 06 spec 01: "MUST usar el regex exacto".
- El filtrado adicional cubre los 3 casos de descarte de spec 01 escenario 2.
- Portable a Bash 3.2 sin dependencias externas.

**Alternativas consideradas**:
- Usar `awk -v RS='\n'` con regex embebido: más complejo, no aporta.
- Usar `pcregrep`: dependencia externa poco portable (spec SHOULD 01 spec 01).

**Consecuencias**:
- (+) Comportamiento determinístico, validable por test.
- (+) Sin falsos positivos por mención coloquial ("el concept doc de repository pattern" sin path literal).
- (-) Si Sol escribe prosa en lugar de paths literales, no se detecta (aceptable, fuera de scope).

### ADR-003: Path relativo hardcodeado (`../../changes/archive/<YYYY-MM>/<slug>/`)

**Contexto**: Spec 02 escenario 4 deja dos opciones: (a) calcular path relativo genérico con `awk`/`sed`/`cd`/`pwd`; (b) hardcodear que concept doc está a `../../` del plan archivado. La realidad del MVP: concept doc siempre vive en `.opencode/context/concept/<slug>.md`, plan archivado vive en `.opencode/changes/archive/<YYYY-MM>/<slug>/`. Comparten `.opencode/` como ancestro común, separados por 2 segmentos (`context/concept` vs `changes/archive/<YYYY-MM>/<slug>`).

**Decisión**: Hardcodear `../../changes/archive/<YYYY-MM>/<slug>/` como path relativo. No usamos `realpath --relative-to` (no es POSIX) ni cálculo genérico (innecesario).

**Rationale**:
- Si la estructura del bundle OKF cambia (`/concept/` deja de estar a 2 niveles de `.opencode/`), esto se rompe. Pero ese cambio sería una nueva feature y este script se actualiza junto con ella.
- Spec 02 escenario 4 explícitamente autoriza esta simplificación: "una alternativa válida es hardcodear que el concept doc siempre está a `../../` del directorio del plan".

**Alternativas consideradas**:
- Cálculo genérico con `awk` splitteando por `/` y contando segmentos: ~15 líneas de código que solo sirven si la estructura del bundle cambia. YAGNI/R14.
- Usar `python3 -c "import os; print(os.path.relpath(...))"`: viola "no python3" de spec 02 MUST 10.

**Consecuencias**:
- (+) Footer literal, predecible, fácil de auditar.
- (+) Cero riesgo de cálculo off-by-one.
- (-) Asunción documentada como comentario en el script (a nivel diseño, no en el código del script mismo por R2).

### ADR-004: Escritura atómica con `mktemp` + `cat >>tmp` + `mv tmp destino`

**Contexto**: `printf ... >> destino` no es atómico: si Pau mata el script a mitad de append, el concept doc queda corrupto. Necesitamos escritura atómica para no perder evidencia histórica (spec 02 MUST 05: "la función de aplicación MUST preservar el contenido original del concept doc").

**Decisión**: Para aplicar el footer:
1. `tmp=$(mktemp "${CONCEPT_DOC}.tmp.XXXXXX")`
2. `cat "$CONCEPT_DOC" "$BLOQUE_FOOTER_TMP" > "$tmp"` (mantener original + append footer)
3. `mv "$tmp" "$CONCEPT_DOC"` (atómico en el mismo filesystem)
4. `rm -f "$BLOQUE_FOOTER_TMP"`

Donde `BLOQUE_FOOTER_TMP` es un archivo con el bloque del footer (generado una sola vez al inicio con `printf '%s\n\n%s\n\n[%s](%s)\n' '## Spec original' '' "$destino_relativo" "$destino_relativo"`).

**Rationale**:
- `mv` dentro del mismo directorio es atómico en POSIX.
- `cat "$original" "$footer_tmp"` preserva bytes originales (no transformación) — el footer solo se appendea.
- Si algo falla entre paso 1 y 3, el `tmp` queda pero el `original` intacto; cleanup del trap limpia el tmp.

**Alternativas consideradas**:
- `printf >> destino`: no atómico; Pau o el sistema podría interrumpir entre printf y sync.
- `sed -i '$a ## Spec original' destino`: portable pero `sed -i` tiene quirks en macOS (`.bak` files), R14 ya tiene `skalling_sed_inplace` pero no la vamos a meter acá para no generar dependencia nueva.
- `awk '{print} END{print "\n## Spec original\n..."}' destino > tmp && mv tmp destino`: similar pero menos legible.

**Consecuencias**:
- (+) Concept doc nunca queda en estado intermedio.
- (+) Portable a Bash 3.2 + macOS sed.
- (-) 4 líneas extra vs printf >>.

### ADR-005: Idempotencia vía `grep -q '^## Spec original$'`

**Contexto**: Spec 02 escenario 3 dice: "MUST NO modificar el archivo si ya tiene un heading `## Spec original`". La regex debe ser exacta al heading (no matchear `### Spec original`, ni `## Spec original X`).

**Decisión**: Helper `validar_footer_existente <concept_doc>`:
```bash
grep -q -E '^## Spec original[[:space:]]*$' "$concept_doc"
```

La regex acepta el heading con o sin espacios trailing (defensa contra trailing whitespace de editores).

**Rationale**:
- Match anclado con `^` y fin de línea (`$` o `[[:space:]]*$` para tolerar trailing space).
- `grep -q` es portable y rápido.

**Alternativas consideradas**:
- `awk '/^## Spec original[[:space:]]*$/ {found=1; exit} END{exit !found}'`: más complejo, no aporta.
- Verificar presencia del path específico del plan: rechaza re-ejecución del mismo plan (correcto), pero también rechaza concept docs con links a otros planes (incorrecto — debería preservarlos todos).

**Consecuencias**:
- (+) Cobertura correcta del caso "preservar el primero" (spec escenario 3).
- (+) Permite que planes subsiguientes NO sobrescriban evidencia histórica.

### ADR-006: Idempotencia del archivo completo (no solo del footer)

**Contexto**: Si Pau corre el script dos veces sobre el mismo plan, el segundo run debe ser no-op (spec éxito criterio: "el segundo run no modifica los concept docs porque ya tienen el footer").

**Decisión**: El detector es determinístico (mismas entradas → mismas salidas). El aplicador verifica `validar_footer_existente` antes de escribir. Si todos los concept docs detectados ya tienen footer, el resumen reporta `preservado: N` y exit 0.

**Rationale**:
- Spec 02 escenario 3 MUST: "MUST seguir procesando los demás concept docs" → no abortar.
- Exit 0 en segundo run es semánticamente correcto (no hubo error, solo no hubo trabajo).

**Consecuencias**:
- (+) Pau puede re-ejecutar el script sin miedo a corromper memoria.
- (+) Tests pueden correr dos veces seguidas sin preparar fixtures distintos.

### ADR-007: Tests invocan aplicador con lista hardcoded vía env var

**Contexto**: Spec 03 escenario 2 permite que el test fuerce al script a correr el módulo de aplicación con una lista hardcoded (en lugar de detectarla desde un plan). Esto aísla la lógica de aplicación de la de detección en los tests.

**Decisión**: Si la variable de entorno `SKALLING_MEMORY_LINK_SOLO_APLICAR` está definida con un path, el script salta el detector y aplica el footer a ese path directamente. Tests usan este flag para testear aplicación con concept docs sintéticos sin armar un plan completo.

**Rationale**:
- Permite tests unitarios de la lógica de aplicación sin overhead de armar fixtures completas de planes.
- Spec 01 escenario 7 (out-of-spec del detector) y spec 02 (aplicación) pueden testearse por separado.

**Alternativas consideradas**:
- Sub-comando CLI `--solo-aplicar`: introduce superficie CLI nueva solo para tests (mala práctica).
- Variable de entorno: estándar en herramientas POSIX (`NO_COLOR`, `DEBUG`, etc.).

**Consecuencias**:
- (+) Tests rápidos y aislados.
- (-) Variable de entorno "mágica" — debe documentarse en el header del script.

### ADR-008: Activación de colores según TTY + identificación `## Spec original` con azul

**Contexto**: El output del script va a Pau (humano), no a un pipeline. Spec no exige colores, pero el patrón del repo los usa.

**Decisión**: Helper `activar_color` setea `MODO_COLOR=1` solo si `[[ -t 1 ]] && [[ -t 2 ]]`. Helpers `imprimir_aplicado`/`imprimir_preservado`/`imprimir_error` consultan `MODO_COLOR`. Si TTY: aplicado verde, preservado azul, error rojo. Sin TTY: literal sin códigos.

**Rationale**:
- Tests corren limpios (`grep` sin ruido ANSI).
- Pau ve colores útiles cuando corre desde su sesión interactiva.

**Alternativas consideradas**:
- `--color=always|never`: overkill para un script auxiliar.
- Sin colores: pierde la legibilidad que tiene drift detection y mem-review.

**Consecuencias**:
- (+) Consistencia visual con `scripts/skalling-drift.sh` y `scripts/mem-review.sh`.
- (-) Si el usuario pipea a `less`, pierde color (esperado, comportamiento Unix).

### ADR-009: Identificadores en español, incluyendo el nombre del script (manteniendo "spec-memory-link" como kebab externo)

**Contexto**: R1 exige identificadores propios en español. La convención del repo permite kebab-case externo (`skalling-drift.sh`) pero camelCase/snake_case interno en español.

**Decisión**:
- **Nombre externo** (archivo + invocación): `scripts/spec-memory-link.sh` (mantiene kebab-case por consistencia con `skalling-drift.sh`).
- **Funciones internas**: `detectar_concept_docs`, `extraer_matches`, `validar_path_concept`, `validar_footer_existente`, `aplicar_footer_a_concept_doc`, `calcular_path_relativo`, `imprimir_resumen`, `validar_argv`, `validar_escribible`, `activar_color`.
- **Variables**: `RAIZ_REPOSITORIO`, `MODO_COLOR`, `LISTA_CONCEPT_DOCS`, `BLOQUE_FOOTER`, `c_verde`, `c_azul`, `c_rojo`, `c_neutro`.

**Rationale**:
- R1 es MUST.
- Mantener el kebab externo "spec-memory-link" es razonable porque es la identidad pública del feature (cf. `skalling-drift.sh`).

**Consecuencias**:
- (+) R1 cumplido al 100%.
- (-) Inconsistencia con `skalling-drift.sh` que sí usa kebab interno (`validar_path_relativo`). Aceptable — son features distintas, cada una cumple R1 a su manera.

### ADR-010: Integración del doctor como `info` (no bloqueante)

**Contexto**: Spec 03 escenario 12 dice: "el doctor debe incluir una línea informativa... no debe incrementar contadores... no debe cambiar el exit code".

**Decisión**: En `setup-team-doctor.sh`, después del bloque "Drift detection" (líneas 361-365), agregar:
```bash
if [[ -f "$SCRIPT_DIR/scripts/spec-memory-link.sh" ]]; then
    info "Spec ↔ Memory link disponible: bash scripts/spec-memory-link.sh <origen> <destino>"
else
    info "Spec ↔ Memory link NO instalado (feature pendiente)"
fi
```

**Rationale**:
- `info()` ya está implementado (línea 70 doctor) y no modifica contadores.
- Patrón idéntico al de drift detection (ADR-005 de drift detection).

**Alternativas consideradas**:
- Nueva sección `check_spec_memory_link()`: pesa demasiado para una línea informativa.

**Consecuencias**:
- (+) 4 líneas de cambio mínimo en el doctor.
- (+) Cero riesgo de regresión de exit code.

### ADR-011: Bump minor de 0.5.0 → 0.6.0

**Contexto**: La versión actual es `0.5.0` (en `VERSION` y `SKALLING_VERSION` del doctor). Spec-memory-link es feature aditiva, backward-compatible (no rompe ningún surface existente, agrega un script nuevo y un sub-paso en Pau).

**Decisión propuesta**: `0.5.0` → `0.6.0` (minor).

**Rationale**:
- SemVer: funcionalidad aditiva backward-compatible = minor (Y).
- No rompe ningún surface existente (no cambia doctor exit code, no modifica APIs, no cambia permisos).
- No es bugfix ni patch (X), no es breaking (Z).

**Alternativas**:
- 0.5.1 (patch): subestima la feature.
- 1.0.0 (major): prematuro; Skalling está pre-1.0.

**Consecuencias**: CHANGELOG entra bajo `[Unreleased]` durante desarrollo, se renombra a `[0.6.0] — YYYY-MM-DD` al cerrar.

---

## Modelo de Datos (Gramática de Match y Footer)

### Match regex (spec 01 escenario 2)

```
match         ::= '\\.opencode/context/concept/[A-Za-z0-9._-]+\\.md'
                con o sin '/' inicial
                con o sin prefijo de repo (ej: 'repo/.opencode/...')
                ejemplo válido: .opencode/context/concept/repo-pattern.md
                ejemplo válido: /repo/.opencode/context/concept/repo-pattern.md
                ejemplo inválido: .opencode/context/concept/../escape.md   (rechaza: '..')
                ejemplo inválido: .opencode/context/concept/foo bar.md    (rechaza: espacio)
                ejemplo inválido: .opencode/context/concept/.md           (rechaza: nombre vacío)
```

### Footer (spec 02 escenario 2)

```markdown

## Spec original

[../../changes/archive/<YYYY-MM>/<slug>/](../../changes/archive/<YYYY-MM>/<slug>/)
```

Donde `<slug>` es el nombre del directorio del plan (último segmento del path destino).

El bloque se genera con:
```bash
BLOQUE_FOOTER=$(printf '%s\n\n%s\n\n[%s](%s)\n' '' '## Spec original' '' "$relativo" "$relativo")
```

Espera `printf '%s\n'` sobre el BLOQUE_FOOTER produce las 5 líneas exactas:
```
(empty)
## Spec original
(empty)
[../../changes/archive/2026-08/spec-memory-link/](../../changes/archive/2026-08/spec-memory-link/)
(empty)
```

Concatenado al final del concept doc (que ya termina con `\n`), produce el resultado esperado:
```
[última línea del concept doc]

## Spec original

[../../changes/archive/.../](../../changes/archive/.../)
```

### Estados del aplicador por concept doc

```
existe_archivo = NO                  → descartar (defensa en profundidad, ya filtrado en detector)
tamaño = 0 bytes                     → error: "está vacío"
tiene ## Spec original               → preservado (idempotencia)
no escribible (chmod a-w)            → error: "no se puede escribir"
normal                              → aplicado (escritura atómica)
```

### Path relativo hardcodeado

```
relativo = "../../changes/archive/<YYYY-MM>/<slug>/"
```

donde:
- `<YYYY-MM>` se extrae del path destino `dirname` (segmento `archive/<YYYY-MM>`).
- `<slug>` es el último segmento del path destino (basename).

Implementación:
```bash
calcular_path_relativo() {
    local destino="$1"
    local segmentos_destino
    IFS='/' read -ra segmentos_destino <<< "$destino"
    local slug="${segmentos_destino[$((${#segmentos_destino[@]} - 1))]}"
    if [[ -z "$slug" || "$slug" = "." || "$slug" = ".." ]]; then
        slug="$(basename "$destino")"
    fi
    printf '../../changes/archive/%s\n' "$slug"  # simplificado: asume YYYY-MM arriba
}
```

Para MVP, simplificamos extrayendo `<YYYY-MM>` del path destino como el segmento inmediatamente anterior al slug. Si Pau pasa `.opencode/changes/archive/2026-08/spec-memory-link/`, los segmentos son `["", ".opencode", "changes", "archive", "2026-08", "spec-memory-link", ""]`, y tomamos `2026-08` como índice `-2` y `spec-memory-link` como índice `-1`.

(Si esto se complica, alternativa más simple: aceptar el path destino como 2 argumentos separados, `<YYYY-MM>` y `<slug>`. Decisión final en implementación si surge fricción — ADR se ajusta si es necesario.)

---

## Patrones aplicados

### POSIX first (R14 ladder)

| Peldaño | Uso en spec-memory-link |
|---|---|
| stdlib | `find`, `grep -E`, `grep -F`, `sed`, `awk`, `dirname`, `basename`, `mktemp` |
| Bash builtin | `case`, `while read`, `[[ =~ ]]` para regex simple |
| 3rd-party | **ninguna** |

`grep -E` con el regex declarado; `mktemp` para escritura atómica; `mv` para rename atómico en mismo FS.

### Bash 3.2 portable

- **No** `declare -A` (arrays asociativos, Bash 4+).
- **No** `mapfile`, `readarray` (Bash 4+).
- **Sí** `case` patterns con globs extendidos.
- **Sí** `[[ "$str" =~ $regex ]]` (3.0+).
- **Sí** arrays indexados: `arr=("a" "b")`; `for x in "${arr[@]}"`.
- **Sí** `IFS='/' read -ra arr` (3.0+).

### Helpers en español (R1)

| Helper | Propósito |
|---|---|
| `validar_argv` | Valida 2 args posicionales (origen, destino) |
| `detectar_concept_docs` | Escanea archivos del plan, retorna lista única |
| `extraer_matches` | Aplica regex a un archivo individual |
| `validar_path_concept` | Filtra por regex + existencia en filesystem |
| `calcular_path_relativo` | Construye path `../../changes/archive/<YYYY-MM>/<slug>/` |
| `validar_footer_existente` | `grep -q '^## Spec original[[:space:]]*$'` |
| `validar_escribible` | `[[ -w archivo ]]` |
| `aplicar_footer_a_concept_doc` | Escritura atómica con `mktemp` + `mv` |
| `imprimir_resumen` | Conteos finales + exit code |
| `imprimir_aplicado` | Línea verde con prefijo `aplicado:` |
| `imprimir_preservado` | Línea azul con prefijo `preservado:` |
| `imprimir_error` | Línea roja con prefijo `error:` |
| `imprimir_advertencia` | Línea azul con prefijo `advertencia:` (referencias rotas) |
| `activar_color` | Setea `MODO_COLOR` según TTY |
| `uso` | Imprime docstring de uso (con `--help`/`-h`) |

### Patrón de exit codes (spec 02 escenario 6)

| Condición | Exit |
|---|---|
| `0` argumentos o `>2` argumentos | `2` (error de invocación) |
| Directorio origen inexistente | `2` |
| Sin archivos escaneables en origen | `2` |
| Matches vacío (plan sin concept docs) | `0` (info, no hubo trabajo) |
| Al menos 1 aplicado o preservado | `0` (éxito) |
| Matches tuvo candidatos pero TODOS fallaron | `1` (fallo agregado) |
| Error interno del script | `1` |

**Nota**: Pau interpreta exit ≠ 0 como "pausar y notificar al usuario" (spec 02 escenario 1).

---

## Seguridad (Validación de paths)

### Anti-traversal

El regex `\.opencode/context/concept/[A-Za-z0-9._-]+\.md` no permite segmentos `..` (la clase de caracteres excluye `/`). Filtro adicional con `grep -v '\.\.'` como defensa redundante.

### Anti-path absoluto

El regex matchea con o sin `/` inicial (spec 01 escenario 2). Si el match tiene `/` inicial, lo descartamos porque concept docs viven siempre como path relativo al repo:

```bash
match="${match#/}"  # strip leading slash
```

### Anti-concept doc vacío

`validar_path_concept` rechaza explícitamente nombre de archivo `.md` solo (regex post-filtro: `grep -v '/\.md$'`).

### No ejecución automática

- El doctor no llama al script — el usuario decide cuándo correrlo.
- Pau invoca el script explícitamente como parte de PASO 5.
- No hay `eval`, no hay `source` de archivos externos, no hay network calls.

### Validación de argv

```bash
validar_argv() {
    if [[ $# -lt 2 ]]; then
        imprimir_error_entrada "Faltan argumentos. Uso: bash spec-memory-link.sh <origen> <destino>"
        return 2
    fi
    if [[ $# -gt 2 ]]; then
        imprimir_error_entrada "Se esperaban 2 argumentos, se recibieron $#"
        return 2
    fi
    if [[ ! -d "$1" ]]; then
        imprimir_error_entrada "$1 no existe o no es directorio"
        return 2
    fi
    if [[ ! -d "$2" ]]; then
        imprimir_error_entrada "$2 (destino) no existe o no es directorio"
        return 2
    fi
    local tiene_archivos="false"
    [[ -f "$1/proposal.md" || -f "$1/design.md" || -f "$1/tasks.md" ]] && tiene_archivos="true"
    [[ -d "$1/specs" ]] && tiene_archivos="true"
    if [[ "$tiene_archivos" == "false" ]]; then
        imprimir_error_entrada "$1 no contiene proposal.md, design.md, tasks.md ni specs/"
        return 2
    fi
}
```

---

## Testing Strategy

### Estructura del archivo de tests

`tests/spec-memory-link.test.sh` sigue el patrón de `tests/skalling-drift.test.sh` (helper `pass`/`fail`/`log`, contadores, `--verbose`, `FIXTURE` con `mktemp -d` y `trap` cleanup) **sin** los comentarios descriptivos (R2 ZERO comments).

### Fixture pattern

```bash
FIXTURE="$(mktemp -d)"
trap 'rm -rf "$FIXTURE"' EXIT

preparar_fixture() {
    local plan_slug="$1"
    local plan_dir="$FIXTURE/.opencode/changes/$plan_slug"
    rm -rf "$plan_dir"
    mkdir -p "$plan_dir/specs"
    mkdir -p "$FIXTURE/.opencode/context/concept"
    mkdir -p "$FIXTURE/scripts"
    cp "$SCRIPT" "$FIXTURE/scripts/spec-memory-link.sh"
}

preparar_concept_doc() {
    local slug="$1"
    local contenido="$2"
    mkdir -p "$FIXTURE/.opencode/context/concept"
    printf '%s\n' "$contenido" > "$FIXTURE/.opencode/context/concept/$slug.md"
}
```

El test crea concept docs en `$FIXTURE/.opencode/context/concept/`, escribe un plan en `$FIXTURE/.opencode/changes/<slug>/`, y corre:

```bash
(cd "$FIXTURE" && bash scripts/spec-memory-link.sh \
    ".opencode/changes/<slug>" \
    ".opencode/changes/archive/2026-08/<slug>")
```

### Cobertura por escenario de spec 03

| Escenario | Test function |
|---|---|
| Estructura del script + bash -n | `test_estructura_script` |
| argv inválido (4 casos: 0/1/3 args, dir inexistente) | `test_argv_invalido` |
| Happy path: múltiples concept docs detectados y aplicados | `test_happy_path_multiples_concept_docs` |
| Sin concept docs afectados (mensaje informativo, exit 0) | `test_sin_concept_docs_afectados` |
| Idempotencia: 2do run no modifica | `test_idempotencia_segundo_run` |
| Preservar el primero: footer pre-existente | `test_preservar_el_primero` |
| Referencia rota no aplica footer | `test_referencia_rota` |
| Concept doc no escribible (skip en macOS root) | `test_concept_doc_no_escribible` o SKIP |
| Errores de entrada (batería completa) | `test_entradas_invalidas_bateria` |
| Formato exacto del footer (últimas líneas) | `test_formato_exacto_footer` |
| Portabilidad Bash 3.2 | `test_portabilidad_bash_3_2` |
| Identificadores en español (R1) | `test_identificadores_en_espanol` |
| Integración doctor info no bloqueante | `test_doctor_info_spec_memory_link` |
| Bump versión + CHANGELOG | `test_release_y_doctor` |

Total estimado: ~15 funciones de test, ~50-70 asserts. Consistente con `tests/skalling-drift.test.sh`.

### Assertions (helpers específicos)

```bash
afirmar_exit_code() {
    set +e
    OUTPUT="$(cd "$FIXTURE" && bash scripts/spec-memory-link.sh "$1" "$2" 2>&1)"
    STATUS=$?
    set -e
    if [[ "$STATUS" -eq "$3" ]]; then pass "$4"; else fail "$4 — exit esperado $3, obtuvo $STATUS"; fi
}

afirmar_aplicado() {
    if [[ "$OUTPUT" == *"aplicado: $1"* ]]; then pass "$2"; else fail "$2 — no contiene 'aplicado: $1'"; fi
}

afirmar_preservado() {
    if [[ "$OUTPUT" == *"preservado: $1"* ]]; then pass "$2"; else fail "$2 — no contiene 'preservado: $1'"; fi
}
```

Patrón compatible con `set -euo pipefail` (spec 03 MUST 6).

---

## Riesgos conocidos

1. **Hardcode del path relativo (ADR-003)**: si alguien reorganiza el bundle OKF (mueve `.opencode/context/concept/` a otra profundidad), el path relativo se rompe. Mitigación: documentado en design.md y como comentario de sección en el script; tests no cubren reorganización porque está fuera de scope.

2. **Concurrencia**: Pau corre el script serializadamente (PASO 5 es single-threaded humano), pero si dos instancias corren a la vez sobre el mismo plan, podrían intentar escribir el mismo concept doc simultáneamente. Mitigación: el `mv` atómico gana-gana (último gana); el contenido es el mismo footer (idempotente), así que el resultado es correcto. Riesgo bajo.

3. **Concept doc con BOM o encoding raro**: el `grep -E` funciona con UTF-8. Si un concept doc tiene BOM Windows (`\xEF\xBB\xBF`), el regex igual matchea (la clase `[A-Za-z0-9._-]` es ASCII puro, no se afecta). El append podría introducir una línea extra vacía. Mitigación: documentado; Pau no genera concept docs con BOM en este repo (todos UTF-8 limpio).

4. **Variantes tipográficas del heading `## Spec original`**: `### Spec original` (subhead), `## Espec original` (typo), `## spec original` (lowercase) → no matchean `^## Spec original[[:space:]]*$`. Mitigación: tests cubren variantes; spec 02 escenario 3 es estricto con el regex.

5. **Diferencia de salida entre TTY y pipe**: con pipe, no hay color. Si Pau redirige `> archivo.txt`, perderá color. Esperado, comportamiento Unix.

6. **Permisos del doctor bajo `--strict`**: el info del doctor NO es bloqueante bajo `--strict` porque `info()` no incrementa `WARN_COUNT`. Verificado con test explícito.

---

## Out of design (explícitamente NO incluido)

Reafirmamos los out-of-scope del `proposal.md` desde el ángulo técnico:

- **Sincronización bidireccional** (spec → concept doc): flujo inverso, ortogonal.
- **Reescritura del footer existente**: la regla es preservar el primero (spec 02 escenario 3 MUST).
- **Validación de que el link sigue vivo**: eso es drift detection, ya cubierto por `scripts/skalling-drift.sh`.
- **Inserción del footer en una posición distinta al final**: el footer siempre va al final.
- **Detección de concept docs fuera de `.opencode/context/concept/`**: fuera de scope MVP.
- **Auto-invocación desde doctor o git hooks**: Pau lo llama manualmente.
- **Parser YAML / JSON / multi-línea**: el footer es append literal, no interpretación.
- **CI / benchmarks de performance / API HTTP / TUI**: no son parte del MVP.
- **Soporte para paths con espacios en concept docs**: regex los rechaza (spec 01 escenario 2 MUST).

---

## Resumen de identificadores claves

| Categoría | Español |
|---|---|
| Script principal | `scripts/spec-memory-link.sh` |
| Script de tests | `tests/spec-memory-link.test.sh` |
| Versión propuesta | `0.5.0` → `0.6.0` (minor) |
| Comandos slash | ninguno (es herramienta CLI) |
| Directorios afectados | `scripts/`, `tests/`, `agents-base/Pau.md`, `setup-team-doctor.sh`, `command/skalling-doctor.md`, `VERSION`, `CHANGELOG.md`, `README.md` |
| Sin cambios en | `constitucion/constitucion.md`, otros agentes, otros scripts, bundle OKF, frontmatter de concept docs |