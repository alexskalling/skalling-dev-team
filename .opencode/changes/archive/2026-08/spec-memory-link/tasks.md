# Tasks: Spec ↔ Memory link

> **Granularidad**: cada tarea ejecutable en 2-5 minutos. TDD estricto: RED → GREEN → REFACTOR dentro de cada tarea.
> **Agrupación**: 4 fases (detector → aplicador → integración Pau + tests → release).
> **Numeración**: jerárquica (1.1, 1.2, 2.1, …).
> **Validación**: cada tarea pasa por Teo → Jhon antes de avanzar. Luz audita el plan completo al final.
> **Constraints no negociables** (ya nos costó 3 re-auditorías):
> - R1 — identifiers en español (`detectar_concept_docs`, no `detect_concept_docs`)
> - R2 — ZERO comentarios en código (ni `# esto hace X`, ni banners descriptivos)
> - R16 — mensajes de commit en español, formato `<tipo>: <qué>`, con permiso del usuario previo
> - Bash 3.2 portable (no `declare -A`, `mapfile`, `readarray`)
> - Tests con `set -euo pipefail` + cleanup con `trap 'rm -rf "$FIXTURE"' EXIT`
> - Tests siguen patrón de `tests/skalling-drift.test.sh` pero SIN sus comentarios descriptivos
> - Spec 02 asume path relativo hardcodeado `../../changes/archive/<YYYY-MM>/<slug>/` (ADR-003)
> - Spec 02 asume escritura atómica con `mktemp` + `mv` (ADR-004)

---

## Fase 1: Detector — parsear plan → listar concept docs afectados

> Cimientos de la lectura. Al terminar esta fase: el script existe, valida su argv, escanea los 4 tipos de archivo, extrae matches con el regex declarado, filtra inválidos, valida existencia en filesystem, deduplica y emite la lista ordenada. Sin side-effects: solo lectura.

- [ ] **1.1** Crear `scripts/spec-memory-link.sh` con shebang, `set -euo pipefail`, doc de uso, helpers de output
   - Archivo: `scripts/spec-memory-link.sh`
   - Primeras líneas: `#!/usr/bin/env bash`, `set -euo pipefail`, `DIRECTORIO_SCRIPT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"`, `RAIZ_REPOSITORIO="$(cd "$DIRECTORIO_SCRIPT/.." && pwd)"`
   - Constantes de color en español: `c_verde`, `c_rojo`, `c_azul`, `c_neutro`, `MODO_COLOR=0`
   - Función `uso()` que imprime docstring de uso a stdout y exit 0 cuando se invoca con `--help` o `-h`
   - Stubs de output: `imprimir_error_entrada`, `imprimir_advertencia`, `imprimir_aplicado`, `imprimir_preservado`, `imprimir_error` (todos escriben a stderr o stdout según corresponda, consultan `MODO_COLOR`)
   - Función stub `activar_color()` que setea `MODO_COLOR` según `[[ -t 1 ]]`
   - NO incluir lógica de detección ni aplicación todavía (solo el cascarón)
   - Test RED primero en `tests/spec-memory-link.test.sh`: `afirmar_archivo_existe "$ROOT/scripts/spec-memory-link.sh"` y `bash -n "$ROOT/scripts/spec-memory-link.sh"` exit 0
   - Valida con Jhon ✓

- [ ] **1.2** Parseo de argv: exigir exactamente 2 args posicionales (`origen`, `destino`), validar que ambos sean directorios
   - Función `validar_argv`: `$# -eq 2`; si no, mensaje a stderr con prefijo `error:` y exit `2`
   - `[[ -d "$1" ]]` y `[[ -d "$2" ]]`; si falla, `imprimir_error_entrada "<path> no existe o no es directorio"` + exit `2`
   - Test RED: invocar con 0 args, 1 arg, 3 args, path origen inexistente, path destino inexistente → exit `2` con mensaje accionable
   - Test RED: mensaje contiene literalmente `<origen>` y `<destino>` (al usuario le ayuda a entender qué argumento es cuál)
   - Valida con Jhon ✓

- [ ] **1.3** Helper `detectar_archivos_escaneables <directorio>` (RED primero)
   - Función retorna, una línea por archivo, los archivos a escanear en este orden:
     1. `<dir>/proposal.md` (si existe)
     2. `<dir>/design.md` (si existe)
     3. `<dir>/tasks.md` (si existe)
     4. `<dir>/specs/*.md` (cada archivo en orden lexicográfico, si el directorio specs/ existe)
   - Implementación con `[[ -f ]]` para los 3 primeros, `find` con `-maxdepth 1 -type f -name '*.md' | sort` para specs
   - Test RED: directorio con los 3 archivos planos + 2 specs → retorna 5 líneas en orden correcto
   - Test RED: directorio con solo `proposal.md` → retorna 1 línea
   - Test RED: directorio con `receipts/foo.md` + `index.md` → NO aparecen en el output
   - Test RED: directorio con `specs/` pero sin `.md` → el directorio specs/ se ignora silenciosamente
   - Valida con Jhon ✓

- [ ] **1.4** Helper `extraer_matches <archivo>` con el regex declarado (RED primero)
   - Función aplica `grep -Eo` con regex `\.opencode/context/concept/[A-Za-z0-9._-]+\.md` al archivo
   - Una línea por match por stdout
   - Strip de `/` inicial si lo tiene (defensa contra matches con slash inicial)
   - Test RED: archivo con 2 menciones literales distintas + 1 mención coloquial sin path → retorna 2 líneas
   - Test RED: archivo con paths con prefijo de repo (`repo/.opencode/...`) → retorna los matches con `.opencode/...` (sin el prefijo)
   - Test RED: archivo con match en backticks, en link markdown, en bloque de código → retorna el match (no interpreta contexto, es texto crudo)
   - Test RED: archivo sin matches → retorna vacío (sin exit code raro)
   - Valida con Jhon ✓

- [ ] **1.5** Helper `filtrar_matches_invalidos <lista>` (RED primero)
   - Recibe una lista de matches por stdin (uno por línea)
   - Filtra con `grep -v` (en cascada) los matches que:
     - Contienen `..` (path traversal)
     - Contienen espacios
     - Terminan en `/.md` (nombre de archivo vacío)
   - Test RED: input con 4 matches (1 válido, 1 con `..`, 1 con espacio, 1 con nombre vacío) → retorna 1 línea
   - Test RED: input vacío → retorna vacío
   - Test RED: input con solo matches inválidos → retorna vacío
   - Valida con Jhon ✓

- [ ] **1.6** Helper `validar_path_concept <match>` que valida regex estricto + existencia en filesystem
   - Recibe un match (un path tipo `.opencode/context/concept/<slug>.md`)
   - Regex post-filtro: rechaza si NO matchea exactamente `\.opencode/context/concept/[A-Za-z0-9._-]+\.md`
   - Verifica existencia: `[[ -f "$RAIZ_REPOSITORIO/$match" ]]`
   - Si no matchea regex estricto: retorna 1 + reporta a stderr `advertencia: match descartado por regex: <match>`
   - Si no existe: retorna 1 + reporta a stderr `advertencia: referencia a concept doc inexistente: <match> (en <archivo-origen>)`
   - Si pasa: retorna 0
   - Test RED: 4 casos (regex OK + existe, regex OK + no existe, regex inválido, mixto)
   - Valida con Jhon ✓

- [ ] **1.7** Helper `detectar_concept_docs <directorio>` — orquesta todo (RED primero)
   - Función top-level del detector: orquesta `detectar_archivos_escaneables` + `extraer_matches` + `filtrar_matches_invalidos` + `validar_path_concept`
   - Para cada archivo escaneable, agrega una etiqueta al match indicando su origen (`archivo:<ruta>`) para que `validar_path_concept` pueda reportar
   - Deduplica con `sort -u` sobre los paths (sin la etiqueta)
   - Output: una línea por concept doc único válido, en orden lexicográfico (sort -u ya da ese orden)
   - Si no hay matches válidos: emite por stdout `spec-memory-link: 0 concept docs afectados por este plan` y exit 0
   - Si hay matches inválidos pero también válidos: reporta los inválidos por stderr y continúa con los válidos
   - Test RED: plan con 2 concept docs distintos + 1 referencia rota → output por stdout tiene 2 líneas + stderr tiene 1 advertencia
   - Test RED: plan con menciones del mismo concept doc en 3 archivos → output por stdout tiene 1 línea (dedup)
   - Test RED: plan sin matches → output contiene `0 concept docs afectados` y exit 0
   - Valida con Jhon ✓
   - **Handoff a Fase 2 cuando: detector corre sin side-effects, argv validado, todos los tests de Fase 1 verdes**

---

## Fase 2: Aplicador — insertar footer idempotente

> Sustancia del MVP. Al terminar esta fase: el script toma una lista de concept docs + el path destino del plan, calcula el path relativo, valida idempotencia, escribe el footer atómicamente a los que NO lo tengan, y emite el resumen consolidado. Pau ya puede invocarlo manualmente con la lista del detector.

- [ ] **2.1** Helper `calcular_path_relativo <destino>` (RED primero)
   - Recibe el path destino completo (ej: `.opencode/changes/archive/2026-08/spec-memory-link/`)
   - Extrae el `<YYYY-MM>` y el `<slug>` del path (segmentos finales)
   - Retorna por stdout `../../changes/archive/<YYYY-MM>/<slug>/`
   - Asunción documentada en `design.md` ADR-003: el concept doc siempre vive a 2 segmentos de `.opencode/`, así que el path relativo hardcodeado es siempre `../../changes/archive/...`
   - Test RED: input `.opencode/changes/archive/2026-08/spec-memory-link/` → output `../../changes/archive/2026-08/spec-memory-link/`
   - Test RED: input con trailing slash vs sin trailing slash → mismo output
   - Test RED: input con path absoluto `/Users/foo/.opencode/changes/archive/2026-08/spec-memory-link/` → output igual (normaliza a relativo)
   - Valida con Jhon ✓

- [ ] **2.2** Helper `validar_footer_existente <concept_doc>` (RED primero)
   - Función ejecuta `grep -q -E '^## Spec original[[:space:]]*$' "$concept_doc"` y retorna su exit code
   - Test RED: concept doc sin la sección → retorna 1
   - Test RED: concept doc con `## Spec original` (exacto, fin de línea) → retorna 0
   - Test RED: concept doc con `### Spec original` (subheading) → retorna 1 (no matchea)
   - Test RED: concept doc con `## Spec original X` (texto extra) → retorna 1 (no matchea)
   - Test RED: concept doc con `## Spec original ` (trailing space) → retorna 0 (regex tolerante)
   - Test RED: archivo inexistente → retorna 1 (grep falla)
   - Valida con Jhon ✓

- [ ] **2.3** Helper `validar_escribible <concept_doc>` (RED primero)
   - Verifica `[[ -w "$concept_doc" ]]` Y `[[ -s "$concept_doc" ]]` (no vacío)
   - Si no escribible: retorna 1 + mensaje de error
   - Si vacío: retorna 1 + mensaje "concept doc vacío"
   - Test RED: archivo escribible no vacío → retorna 0
   - Test RED: archivo con chmod `a-w` → retorna 1
   - Test RED: archivo de 0 bytes → retorna 1
   - Test RED: archivo inexistente → retorna 1
   - Nota portable: tests de permisos pueden marcarse SKIP en macOS root (spec 03 escenario 8)
   - Valida con Jhon ✓

- [ ] **2.4** Helper `aplicar_footer_a_concept_doc <concept_doc> <path_relativo>` (RED primero)
   - Construye el bloque del footer con `printf '%s\n\n%s\n\n[%s](%s)\n' '' '## Spec original' '' "$path_relativo" "$path_relativo"`
   - Escritura atómica:
     1. `tmp_bloque=$(mktemp)` + escribir bloque ahí
     2. `tmp_destino=$(mktemp "${concept_doc}.tmp.XXXXXX")`
     3. `cat "$concept_doc" "$tmp_bloque" > "$tmp_destino"`
     4. `mv "$tmp_destino" "$concept_doc"`
     5. `rm -f "$tmp_bloque"`
   - Usa `trap` local para limpiar `tmp_bloque` si el script aborta a mitad (defensa en profundidad)
   - Test RED: concept doc sin footer + path destino → archivo termina con bloque exacto del footer
   - Test RED: verificar que el archivo termina con `\n` (preserva trailing newline del original)
   - Test RED: verificar que el frontmatter YAML del concept doc queda intacto (leer las primeras 8 líneas, comparar)
   - Test RED: el `mktemp` deja un archivo temporal solo si `mv` falla → el cleanup funciona
   - Valida con Jhon ✓

- [ ] **2.5** Función `procesar_concept_doc <concept_doc> <path_relativo>` (RED primero)
   - Orquesta: `validar_footer_existente` → si existe, `imprimir_preservado` y return 0
   - `validar_escribible` → si falla, `imprimir_error` y return 1
   - `aplicar_footer_a_concept_doc` → si OK, `imprimir_aplicado` y return 0
   - Test RED: concept doc sin footer → output contiene `aplicado: <path>` y archivo modificado
   - Test RED: concept doc con footer pre-existente → output contiene `preservado: <path> (ya enlazado)` y archivo NO modificado (comparar hash antes/después)
   - Test RED: concept doc no escribible → output contiene `error: no se puede escribir <path>` y procesamiento continúa
   - Valida con Jhon ✓

- [ ] **2.6** Función `principal` que orquesta detector + aplicador + exit code (RED primero)
   - Llama `validar_argv` (exit 2 si falla)
   - Llama `detectar_concept_docs "$1"` para obtener la lista
   - Si lista vacía → imprime `spec-memory-link: 0 concept docs afectados por este plan` + exit 0
   - Calcula `path_relativo` con `calcular_path_relativo "$2"`
   - Para cada concept doc en la lista: llama `procesar_concept_doc`
   - Cuenta aplicados, preservados, errores en variables globales
   - `imprimir_resumen`: emite 3 líneas (`aplicados: N`, `preservados: M`, `errores: K`)
   - Exit code: 0 si al menos 1 aplicado O preservado, 1 si todos los matches fallaron
   - Test RED: fixture con 2 concept docs válidos + 1 referencia rota → exit 0, aplicados=2, preservados=0, errores=0, stderr tiene 1 advertencia
   - Test RED: re-ejecutar el script sobre el mismo plan → exit 0, aplicados=0, preservados=2 (idempotencia)
   - Test RED: fixture con 1 concept doc no escribible (chmod a-w) → exit 1, aplicados=0, preservados=0, errores=1
   - Valida con Jhon ✓
   - **Handoff a Fase 3 cuando: script end-to-end funciona, footer correcto, idempotencia verificada, exit codes consistentes**

---

## Fase 3: Integración en Pau.md + tests finales de Pau

> Pau ya tiene PASO 5 con archivado. Se le agrega el sub-paso explícito de invocar el script antes del `git mv`. Se actualizan los tests de Pau para verificar la invocación.

- [ ] **3.1** Modificar `agents-base/Pau.md` PASO 5 — agregar sub-paso de link antes del `git mv`
   - Archivo: `agents-base/Pau.md`, líneas 177-189 (PASO 5 existente)
   - Insertar como sub-paso 1, antes del `mv`/`git mv` existente:
     ```markdown
     1. **Enlazar concept docs a la spec** (cuando aplique): corro `bash scripts/spec-memory-link.sh <dir-origen> <dir-destino>` antes de mover la carpeta. El script agrega el footer `## Spec original` a cada concept doc afectado, con link relativo al path final del plan archivado. Si el script falla (exit ≠ 0), pauso y notifico al usuario.
     ```
   - Renumerar el sub-paso de `mv` (actual sub-paso 1) como 2.
   - Al final del PASO 5, agregar el reporte de Pau (spec 02 escenario 1):
     ```markdown
     Al finalizar, reporto al usuario:
     ```
     Concept docs enlazados a este plan:
     - .opencode/context/concept/<slug>.md
     ```
     (si la lista está vacía, omito la sección).
     ```
   - NO eliminar ni reordenar nada del PASO 5 existente.
   - NO agregar permisos nuevos al frontmatter (los actuales ya cubren `edit: .opencode/context/**/*.md: allow` y `bash: "*": ask`).
   - Test RED: `grep -q 'spec-memory-link' agents-base/Pau.md` y `grep -q 'Spec original' agents-base/Pau.md`
   - Test RED: PASO 5 sigue conteniendo la mención de `mv`/`git mv` y `<YYYY-MM>` (no se rompió nada)
   - Valida con Jhon ✓

- [ ] **3.2** Agregar tests finales al suite — consolidado de cobertura end-to-end
   - Archivo: `tests/spec-memory-link.test.sh`
   - Tests consolidados que verifican el flujo Pau completo (no per-espec):
     - `test_pau_referencia_spec_memory_link`: Pau.md menciona "spec-memory-link" y "Spec original"
     - `test_pau_paso_5_intacto`: Pau.md PASO 5 sigue conteniendo las menciones de archivado preexistentes
     - `test_pau_reporte_concept_docs_enlazados`: Pau.md describe el reporte de concept docs enlazados al final del PASO 5
   - Tests de regresión específicos:
     - `test_idempotencia_tres_runs`: ejecutar 3 veces sobre la misma fixture → tercero no modifica nada
     - `test_preservar_primero_con_link_externo`: concept doc con link a `archive/2026-05/otro-plan/` → no se sobrescribe con el nuevo
   - Valida con Jhon ✓
   - **Handoff a Fase 4 cuando: Pau referencia el script, tests consolidados verdes, no hay regresiones**

---

## Fase 4: Doctor + release (bump v0.6.0 + CHANGELOG + README)

> Empaquetado para salir. Integra el doctor como info no bloqueante, documenta el comando, bumpea versión, valida regresión global, archiva.

- [ ] **4.1** Integración informativa en `setup-team-doctor.sh`
   - Archivo: `setup-team-doctor.sh`, después del bloque "Drift detection" (líneas 361-365)
   - Agregar (siguiendo el patrón idéntico al de drift detection, ADR-010):
     ```bash
     if [[ -f "$SCRIPT_DIR/scripts/spec-memory-link.sh" ]]; then
         info "Spec ↔ Memory link disponible: bash scripts/spec-memory-link.sh <origen> <destino>"
     else
         info "Spec ↔ Memory link NO instalado (feature pendiente, ver .opencode/changes/spec-memory-link/)"
     fi
     ```
   - Test RED: `grep -q 'Spec ↔ Memory link' setup-team-doctor.sh` retorna match
   - Valida con Jhon ✓

- [ ] **4.2** Documentar en `command/skalling-doctor.md`
   - Archivo: `command/skalling-doctor.md`
   - Agregar fila en la tabla "Salida": `| Spec ↔ Memory link | ℹ info (manual vía \`bash scripts/spec-memory-link.sh\`) |`
   - Agregar párrafo bajo "Otros findings frecuentes" describiendo que spec-memory-link es ejecución manual, no automática (paralelo al de drift detection, líneas 47-48)
   - Test RED: `grep -q 'spec-memory-link' command/skalling-doctor.md` y `grep -q 'ejecución manual' command/skalling-doctor.md`
   - Valida con Jhon ✓

- [ ] **4.3** Documentar en `README.md` — sección de features
   - Archivo: `README.md`
   - Agregar entrada en la sección que lista features (si existe) o crear una subsección breve sobre spec-memory-link
   - Texto: explica que Pau enlaza concept docs a la spec que los originó al archivar, vía `bash scripts/spec-memory-link.sh`
   - Test RED: `grep -qi 'spec-memory-link' README.md` y `grep -q 'scripts/spec-memory-link.sh' README.md`
   - Valida con Jhon ✓

- [ ] **4.4** Bump de versión `0.5.0` → `0.6.0` (propuesta en ADR-011)
   - Archivos a modificar (verificarlos con `grep -r "0.5.0" --include="*.sh" .` antes):
     - `VERSION` (`__version__ = "0.5.0"` → `"0.6.0"`)
     - `setup-team-doctor.sh` (`SKALLING_VERSION="0.5.0"` → `"0.6.0"`)
     - Otros scripts que lleven el número hardcodeado (verificar con grep)
   - Test RED: `grep -r "0.6.0" --include="*.sh" .` aparece; `grep -r "0.5.0" --include="*.sh" .` ya NO aparece (en contexto de versión)
   - Valida con Jhon ✓

- [ ] **4.5** CHANGELOG entrada bajo `[Unreleased]`, luego renombrar a `[0.6.0]`
   - Archivo: `CHANGELOG.md`
   - Estructura bajo `[Unreleased]`:
     - `### Added`: `scripts/spec-memory-link.sh` (CLI de Pau para enlazar concept docs a specs archivadas), `tests/spec-memory-link.test.sh`, integración informativa en doctor, documentación en `command/skalling-doctor.md` y `README.md`
     - `### Changed`: `agents-base/Pau.md` (PASO 5 extendido con sub-paso de link)
     - `### Security`: nada nuevo
   - Al cerrar (después de Luz validar), renombrar `## [Unreleased]` → `## [0.6.0] — YYYY-MM-DD` y agregar nuevo `## [Unreleased]` arriba
   - Valida con Pau ✓

- [ ] **4.6** Test de integración del doctor (Escenario 12 spec 03)
   - Test `test_doctor_info_spec_memory_link` en `tests/spec-memory-link.test.sh`
   - Setup: stub global con `scripts/spec-memory-link.sh` presente (vía `cp` a `$OPENCODE_DIR/scripts/`), instancia proyecto vacía con `.opencode/`
   - Aserciones: output del doctor contiene `ℹ Spec ↔ Memory link`; no contiene `⚠ Spec` ni `✗ Spec`; exit 0 normal; exit 0 con `--strict` sin findings propios
   - Patrón heredado de `test_release_y_doctor` en `tests/skalling-drift.test.sh` (líneas 1622-1696)
   - Valida con Jhon ✓

- [ ] **4.7** Regresión completa + auditoría Luz + archivado Pau
   - Comando: `bash tests/setup.test.sh` + `bash tests/skalling-drift.test.sh` + `bash tests/spec-memory-link.test.sh` + cualquier otro `tests/*.test.sh` que ya exista
   - Cero regresiones (todos los tests verdes)
   - Cero `bash -n` errors en ningún script
   - Cero uso de `declare -A`/`mapfile`/`readarray` en scripts nuevos (verificar con grep)
   - **Auditoría Luz**: `bash -n scripts/spec-memory-link.sh` + `bash -n tests/spec-memory-link.test.sh` + `grep -E "declare -A|mapfile|readarray"` sobre los nuevos archivos (debe ser vacío) + análisis estático de path traversal / idempotencia / formato footer
   - Tras Luz PASSED: Pau archiva `.opencode/changes/spec-memory-link/` completo a `.opencode/changes/archive/2026-08/spec-memory-link/`
   - Pau actualiza `.opencode/context/log.md` con la entrada de archivado
   - Valida con Jhon ✓ (regresión) + Luz ✓ (quality gate) + Pau ✓ (archivado)

---

## Estimación

| Fase | Tareas | Tiempo estimado |
|---|---|---|
| 1: Detector | 7 | ~50 min |
| 2: Aplicador | 6 | ~50 min |
| 3: Integración Pau + tests | 2 | ~25 min |
| 4: Release | 7 | ~45 min |
| **Total** | **22** | **~3.5h** |

---

## Reglas de ejecución

1. **TDD obligatorio**: cada tarea de implementación tiene RED primero (test que falla), GREEN después (código mínimo), REFACTOR al final.
2. **R2 — cero comentarios**: el código de `scripts/spec-memory-link.sh` y `tests/spec-memory-link.test.sh` no tiene ni banners descriptivos ni comentarios inline. La claridad viene de identificadores y tests.
3. **R1 — español**: funciones, variables, constantes y mensajes al usuario en español. `detectar_concept_docs`, no `detect_concept_docs`. Excepción: el nombre externo del script (`spec-memory-link.sh`) conserva el kebab por consistencia con `skalling-drift.sh`.
4. **R16 — commits en español**: mensajes propuestos pero NO commiteados sin permiso explícito del usuario. Formato: `<tipo>: <qué>`. Tipos válidos: `feat`, `fix`, `refactor`, `docs`, `test`, `chore`. Presentación previa: scope (archivos a tocar) → espera "ok" → commit.
5. **Bash 3.2 portable**: prohibido `declare -A`, `mapfile`, `readarray`. Globs OK, `[[ =~ ]]` OK, arrays indexados OK, `IFS='/' read -ra arr` OK.
6. **Tests con cleanup**: `trap 'rm -rf "$FIXTURE"' EXIT` en línea 8 del test, antes de cualquier operación.
7. **Valida con Jhon por tarea**: no acumular cambios entre check-points. Si una tarea falla, fixear antes de avanzar.
8. **Patrón de tests sin comentarios**: copiar estructura de `tests/skalling-drift.test.sh` (helpers, contadores, traps, `--verbose`) **pero suprimir todos sus comentarios descriptivos** (los de `# ────── ──` headers y los inline). El spec 03 MUST 3 lo exige.
9. **Sin scripts de un solo uso**: si una tarea pide algo de 5 líneas que cabe inline, no crear archivo nuevo. YAGNI/R14.
10. **Ayudas externas prohibidas**: no usamos `shellcheck` como gate (puede que no esté instalado en todos lados), aunque es buena práctica tenerlo localmente. Validamos con `bash -n` + tests.
11. **Asunción de path relativo**: `../../changes/archive/<YYYY-MM>/<slug>/` (ADR-003). NO se calcula genéricamente. Si la estructura del bundle OKF cambia en el futuro, se ajusta este ADR y se regenera el footer.

---

## Defaults propuestos por Sol (registrados en `design.md`)

Los siguientes huecos de las specs no estaban cerrados. Sol propone lo siguiente y los ha registrado como ADRs — quedan abiertos a override del usuario antes de Fase 1.

| Hueco | Default propuesto |
|---|---|
| Bump de versión | `0.5.0` → `0.6.0` (minor, feature aditiva) |
| Estructura del script | Single-file con dos fases lógicas (detectar + aplicar) en el mismo archivo |
| Regex de detección | `\.opencode/context/concept/[A-Za-z0-9._-]+\.md` (fija en spec 01 escenario 2) |
| Filtro de matches inválidos | `grep -v` en cascada: rechaza `..`, espacios, `/.md` vacío |
| Deduplicación | `sort -u` sobre el path del concept doc |
| Orden de archivos escaneados | `proposal.md` → `design.md` → `tasks.md` → `specs/*.md` (lexicográfico) |
| Orden de concept docs en output | Lexicográfico sobre el path (sort -u) |
| Path relativo al concept doc | `../../changes/archive/<YYYY-MM>/<slug>/` hardcodeado (ADR-003) |
| Detección de idempotencia | `grep -q -E '^## Spec original[[:space:]]*$'` |
| Escritura del footer | Atómica: `mktemp` + `cat orig + bloque > tmp` + `mv tmp orig` |
| Activación de colores | Solo si TTY (`[[ -t 1 ]]`) |
| Identificadores de color | `c_verde`, `c_azul`, `c_rojo`, `c_neutro` (español) |
| Exit codes | `0` éxito, `1` fallo agregado, `2` error de argv |
| Pre-prefixes de output | `aplicado:` verde, `preservado:` azul, `error:` rojo, `advertencia:` azul (stderr) |
| Integración doctor | 1 línea `info` después del bloque drift detection (no nueva sección) |
| Variable de entorno para tests | `SKALLING_MEMORY_LINK_SOLO_APLICAR` (bypass detector, lista hardcoded) |
| Mensaje cuando no hay matches | `spec-memory-link: 0 concept docs afectados por este plan` (spec 01 escenario 6) |
| Manejo de errores por archivo | Continuar batch, reportar individualmente, no abortar |
| Validación de argv | 2 args posicionales, ambos directorios existentes, origen con archivos escaneables |