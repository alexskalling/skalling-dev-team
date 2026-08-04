# Tasks: Drift detection para specs archivadas

> **Granularidad**: cada tarea ejecutable en 2-5 minutos. TDD estricto: RED → GREEN → REFACTOR dentro de cada tarea.
> **Agrupación**: 5 fases (foundation → verificadores → validación entrada → robustez → release).
> **Numeración**: jerárquica (1.1, 1.2, 2.1, …).
> **Validación**: cada tarea pasa por Teo → Jhon antes de avanzar. Luz audita el plan completo al final.
> **Constraints no negociables** (ya nos costó 3 re-auditorías):
> - R1 — identifiers en español (`verificar_claim`, no `verify_claim`)
> - R2 — ZERO comentarios en código (ni `# esto hace X`, ni banners descriptivos)
> - R16 — mensajes de commit en español, formato `<tipo>: <qué>`, con permiso del usuario previo
> - Bash 3.2 portable (no `declare -A`, `mapfile`, `readarray`)
> - Tests con `set -euo pipefail` + cleanup con `trap`
> - Tests siguen patrón de `tests/setup.test.sh` pero SIN sus comentarios descriptivos

---

## Fase 1: Foundation — esqueleto + parser del bloque + primer happy path

> Cimientos del CLI. Al terminar esta fase: el script existe, valida su argv, recorre `specs/*.md`, reconoce el bloque `## Verificación`, y pasa 1 test de happy path con un solo claim `archivo:` verde.

- [ ] **1.1** Crear `scripts/skalling-drift.sh` con shebang, `set -euo pipefail`, doc de uso
  - Archivo: `scripts/skalling-drift.sh`
  - Primeras líneas: `#!/usr/bin/env bash`, `set -euo pipefail`, `SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"`, `REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"`
  - Constantes de color en español: `c_verde`, `c_rojo`, `c_azul`, `c_neutro`, `MODO_COLOR=0`
  - Función stub `uso()` que imprime docstring de uso a stdout y exit 0
  - Función stub `imprimir_error_entrada` que escribe a stderr
  - NO incluir lógica de verificación todavía (solo el cascarón)
  - Test RED primero en `tests/skalling-drift.test.sh`: `afirmar_archivo_existe "$ROOT/scripts/skalling-drift.sh"` y `bash -n "$ROOT/scripts/skalling-drift.sh"` exit 0
  - Valida con Jhon ✓

- [ ] **1.2** Parseo de argv: exigir exactamente 1 path posicional, validar que sea directorio
  - Función `validar_argv`: `$# -eq 1`; si no, mensaje a stderr `"Uso: bash skalling-drift.sh <plan-archivado>"` + exit 1
  - `[[ -d "$1" ]]` sino `imprimir_error_entrada "<plan> no existe o no es directorio"` + exit 1
  - Test RED: invocar sin args, con 2 args, con path inexistente → exit 1
  - Valida con Jhon ✓

- [ ] **1.3** Listar specs en orden lexicográfico
  - Función `listar_specs "<plan_dir>"` que retorna `$plan_dir/specs/*.md` ordenados vía `find ... -maxdepth 1 -type f -name '*.md' | sort`
  - Validar que `specs/` exista; si no, error a stderr + exit 1
  - Validar que la lista no esté vacía; si sí, `imprimir_error_entrada "specs/ sin archivos .md"` + exit 1
  - Test RED: fixture con `specs/` vacío → exit 1; fixture con 2 specs → orden lexicográfico correcto
  - Valida con Jhon ✓

- [ ] **1.4** Helper `extraer_bloque_verificacion "<spec_path>"` (RED primero)
  - Función lee línea por línea (while IFS= read -r), estado `fuera`/`dentro`
  - Inicio: `[[ "$linea" = "## Verificación" ]]` → `dentro`
  - Fin: `[[ "$linea" == "## "* ]]` (mientras `fuera == false`) → break
  - Líneas en `dentro` se emiten por stdout para que main las procese
  - Líneas fuera del bloque se ignoran
  - Test RED: fixture con 1 spec que tiene bloque + texto narrativo + heading `## Otra cosa` después → solo se emiten las líneas del bloque
  - Test RED: fixture con `### Verificación` (3 hashes) → bloque NO se detecta (debe emitir nada)
  - Test RED: fixture sin bloque `## Verificación` → emitir nada, exit 1 por cero claims
  - Valida con Jhon ✓

- [ ] **1.5** Stub de `verificar_claim` que solo acepta `archivo:` por ahora
  - Dispatch: `case "$linea" in "- archivo:"*) verificar_archivo "${linea#- archivo: }" ;; *) ;; esac`
  - Stub `verificar_archivo "<ruta>"` retorna 0 (todo PASS) — será reemplazado en Fase 2.1
  - Test RED: integrar `extraer_bloque_verificacion` + `verificar_claim` en `main`, fixture con 1 claim `- archivo: foo.md` válido → exit 0 y stdout contiene `PASS` o `✓` (sin asumir color)
  - Valida con Jhon ✓

- [ ] **1.6** Happy path test #1: fixture autocontenida con 1 claim `archivo:` válido
  - Test `test_happy_path_un_archivo` en `tests/skalling-drift.test.sh`
  - Helper `preparar_fixture "<plan-slug>"` crea `$FIXTURE/scripts/` + copia del script + `agents-base/`
  - Crea `$FIXTURE/agents-base/Alex.md`, `$FIXTURE/.opencode/changes/archive/2026-08/<plan>/specs/spec-unica.md` con bloque `## Verificación` y `- archivo: agents-base/Alex.md`
  - Aserciones: exit 0; output contiene `PASS` o `✓`; exit 1 si el archivo no existe
  - Valida con Jhon ✓
  - **Handoff a Fase 2 cuando: skeleton corre, `bash -n` pasa, 1 test verde**

---

## Fase 2: Verificadores por tipo (`archivo` + `count` + `contiene`) + mixto

> Sustancia del MVP. Cada tipo tiene su verificador + helper. Al terminar: el script maneja los 3 tipos canónicos y reporta PASS/FAIL correctamente en suites mixtas.

- [ ] **2.1** Helper `validar_path_relativo "<ruta>"` (RED primero)
  - Reglas MUST de spec 02 escenario 2: no vacío, no empieza con `/` ni `~`, sin segmentos `..`, sin espacios
  - Output a stderr en español si falla, retorna 1; retorna 0 si OK
  - Implementación: split por `/` (con `IFS='/'`), iterar segmentos, rechazar si cualquiera es `..` o vacío
  - Test RED: fixture con paths válidos/inválidos, asserts sobre cada caso
  - Valida con Jhon ✓

- [ ] **2.2** Verificador `archivo:` real (reemplaza stub de Fase 1.5)
  - `verificar_archivo "<ruta>"`: 1) llama `validar_path_relativo`; 2) si OK, `[[ -f "$REPO_ROOT/$ruta" ]]`
  - Reporta a `imprimir_linea_resultado` con estado PASS o FAIL + ruta + causa
  - Test RED: fixture con archivo que existe → PASS; archivo borrado → FAIL; directorio en lugar de archivo → FAIL
  - Valida con Jhon ✓

- [ ] **2.3** Helper `contar_archivos "<directorio>"` (RED primero)
  - Implementación: `find "$directorio" -maxdepth 1 -type f 2>/dev/null | wc -l | tr -d ' '`
  - Retorna número entero por stdout
  - Si directorio no existe → imprime `0` a stdout + warning a stderr (no aborta)
  - Test RED: fixture con 3 archivos + 0 directorios cuenta 3; con directorio vacío cuenta 0; cuenta incluye ocultos (decisión ADR-007 — documentar en el test)
  - Valida con Jhon ✓

- [ ] **2.4** Verificador `count:` real
  - `verificar_count "<linea>"`: parsea `^([0-9]+) (.+) en (.+)$` con `[[ =~ ]]` (3.0+)
  - Compara `(esperado, observado)` con `total_aprobados` / `total_fallidos`
  - Reporta FAIL mostrando esperado y observado (spec escenario 3 MUST)
  - Test RED: 8 archivos reales en fixture → PASS; cantidad incorrecta → FAIL con mensaje conteniendo esperado y observado
  - Valida con Jhon ✓

- [ ] **2.5** Helper `archivo_contiene "<texto>" "<archivo>"` (RED primero)
  - Implementación: `grep -Fq -- "$texto" "$archivo" 2>/dev/null`; retorna exit de grep
  - Si archivo no existe, retorna 1
  - **NO** regex, **NO** case-insensitive — exactamente literal case-sensitive
  - Test RED: texto presente → 0; texto ausente → 1; archivo ausente → 1; texto con caracteres especiales (`"`, `*`) → trata literal
  - Valida con Jhon ✓

- [ ] **2.6** Verificador `contiene:` real
  - `verificar_contiene "<linea>"`: parsea `^"([^"]+)" en (.+)$` con `[[ =~ ]]`
  - Llama `archivo_contiene`; reporta PASS o FAIL con texto y archivo
  - Test RED: archivo contiene texto → PASS; texto ausente → FAIL; archivo ausente → FAIL con mensaje claro
  - Valida con Jhon ✓

- [ ] **2.7** Dispatch completo en `verificar_claim`
  - `case "$linea" en "- archivo: "*|- count: "*|- contiene: "*|*)` cubre los 3 tipos
  - Cualquier prefijo reconocido con gramática rota → `claim_malformado` + FAIL + `total_reconocidos++` para que no cuente como "0 claims"
  - Implementar `total_reconocidos` y `total_aprobados`, `total_fallidos`
  - Test RED: spec con `- count: ocho en foo` (prefijo OK, gramática rota) → FAIL global con mensaje accionable, exit 1
  - Valida con Jhon ✓

- [ ] **2.8** Test de drift mixto
  - `test_drift_mixto`: fixture con 4 specs, mezcla de PASS y FAIL (1 archivo real, 1 archivo borrado, 1 count correcto, 1 count incorrecto)
  - Aserciones: exit 1; output contiene ambos `PASS` y `FAIL`; se procesaron todos los claims (no para en el primer FAIL)
  - Valida con Jhon ✓
  - **Handoff a Fase 3 cuando: los 3 tipos cubren PASS y FAIL en escenarios aislados + drift mixto verde**

---

## Fase 3: Validación de entrada + claims malformados (cobertura de Escenario 6 spec 01)

> Robustez de input. Cubre los 8 casos del Escenario 6 de spec 01 y el caso "claims malformados" de spec 02 escenario 3.

- [ ] **3.1** Mensajes de error a stderr accionables para cada caso de entrada
  - Sin args: `"Falta el argumento <plan>. Uso: bash skalling-drift.sh <plan-archivado>"`
  - Plan inexistente: `"<path> no existe o no es directorio"`
  - Plan sin `specs/`: `"<plan> no contiene directorio specs/"`
  - `specs/` sin `.md`: `"<plan>/specs/ no contiene archivos .md"`
  - Cero claims reconocidos: `"Ninguna spec contiene claims válidos bajo '## Verificación'"`
  - Test RED: cada mensaje aparece literalmente en stderr; cada invocación retorna exit 1
  - Valida con Jhon ✓

- [ ] **3.2** Validación de paths: rechazar absolutos, `..`, con espacios
  - `validar_path_relativo` rechaza: `/abs/foo`, `~/foo`, `../foo`, `foo/../bar`, `foo bar/baz`, string vacía
  - Cada rechazo produce error a stderr + claim FAIL + exit 1
  - Test RED: 6 specs en fixture con un path problemático cada una; asserts de stderr y exit 1
  - Valida con Jhon ✓

- [ ] **3.3** Cobertura del caso "claims malformados"
  - Spec con `- archivo:` sin path después → malformado
  - Spec con `- count: ocho agentes en foo` → malformado
  - Spec con `- contiene: "" en foo` (texto vacío) → malformado
  - Spec con `- contiene: "txt" en` sin archivo → malformado
  - Cada malformado = FAIL global (spec escenario 3 spec 02)
  - Test RED: 1 spec por caso, asserts FAIL + exit 1 + mensaje identifica el typo
  - Valida con Jhon ✓

- [ ] **3.4** Test consolidado de errores de entrada (Escenario 6 spec 01)
  - `test_entradas_invalidas`: batería de invocaciones, cada una verifica exit 1 + mensaje accionable en stderr
  - 8 sub-tests: sin args, 2 args, plan inexistente, no directorio, sin `specs/`, `specs/` sin `.md`, sin claims reconocidos, path absoluto
  - Helper `expect_exit_1_with_stderr "regex_del_mensaje" "descripcion"`
  - Valida con Jhon ✓
  - **Handoff a Fase 4 cuando: todas las entradas inválidas retornan 1 con mensaje claro**

---

## Fase 4: Robustez (TTY colors, límites del bloque, portabilidad Bash 3.2)

> Refactors finales. Sin cambios funcionales nuevos — solo mejoras de output, cobertura de bordes, y verificación de constraints no negociables.

- [ ] **4.1** Activación de colores según TTY
  - `activar_color` setea `MODO_COLOR=1` solo si `[[ -t 1 ]] && [[ -t 2 ]]`; sino `0`
  - Helpers `imprimir_ok`, `imprimir_fallo`, `imprimir_linea_resultado` consultan `MODO_COLOR`
  - Test RED: invocar con `| cat` → output sin `\033[`; invocar desde script que captura stdout → no-color por default
  - Valida con Jhon ✓

- [ ] **4.2** Resumen final y formato de línea
  - Formato por línea: `  ${c_verde}✓${c_neutro} archivo: agents-base/Alex.md   (spec: 01-foo.md)` (sin colores si no TTY)
  - Resumen: `── Resultado ──` con `total_aprobados`, `total_fallidos`, `total_reconocidos`
  - Si `total_reconocidos == 0`, NO imprimir resumen PASS, solo error accionable
  - Test RED: fixture con PASS y FAIL → output contiene las 3 métricas correctas
  - Valida con Jhon ✓

- [ ] **4.3** Límites del bloque: claims fuera de `## Verificación` no se cuentan
  - Test RED: spec con `- archivo: foo.md` antes del bloque, dentro del bloque, y después del bloque → solo el del medio se procesa
  - Test RED: spec con `### Verificación` (subhead), `## Verificación` (head), `## Verificaciones` (variante) → solo el head canónico abre el bloque
  - Valida con Jhon ✓

- [ ] **4.4** Validación de portabilidad Bash 3.2 (Escenario 8 spec 03)
  - Test RED 4.4a: `bash -n scripts/skalling-drift.sh` exit 0
  - Test RED 4.4b: `grep -E "declare -A|\bmapfile\b|\breadarray\b" scripts/skalling-drift.sh` retorna vacío (exit 1)
  - Test RED 4.4c: comportamiento real se invoca con `bash scripts/skalling-drift.sh`, no requiere bit ejecutable
  - Valida con Jhon ✓

- [ ] **4.5** Refactor + verificación de R1 (identificadores en español)
  - `grep -E "^[[:space:]]*(function )?[a-zA-Z_]+=" scripts/skalling-drift.sh` para listar funciones/variables; revisar visualmente que son en español (`verificar_*`, `contar_*`, `archivo_*`, `imprimir_*`, etc.)
  - Documentar el grep en `tests/skalling-drift.test.sh` como `test_identificadores_en_espanol`
  - NO comentario en código; el assert vive en el test (R2 OK)
  - Valida con Jhon ✓
  - **Handoff a Fase 5 cuando: tests verdes, color TTY, limites cubiertos, portabilidad validada, R1 auditada**

---

## Fase 5: Release + auditoría + archivado

> Empaquetado para salir. Integra el doctor, documenta, bumpea versión, valida regresión global, archiva.

- [ ] **5.1** Integración informativa en `setup-team-doctor.sh`
  - Archivo: `setup-team-doctor.sh`
  - Al **final** de `check_project_install()` (después del bloque "Changes (SDD)", antes de la posible invocación a `check_memory_health()`), agregar:
    ```bash
    if [[ -f "$SCRIPT_DIR/scripts/skalling-drift.sh" ]]; then
        info "Drift detection disponible: bash scripts/skalling-drift.sh <plan-archivado>"
    else
        info "Drift detection NO instalado (futuro feature, ver .opencode/changes/skalling-drift-detection/)"
    fi
    ```
  - Test RED: `grep "Drift detection" setup-team-doctor.sh` retorna match
  - Valida con Jhon ✓

- [ ] **5.2** Documentar en `command/skalling-doctor.md`
  - Archivo: `command/skalling-doctor.md`
  - Agregar fila en la tabla "Salida": `| Drift detection | ℹ info (manual via bash scripts/skalling-drift.sh) |`
  - Agregar párrafo bajo "Otros findings frecuentes" describiendo que drift detection es ejecución manual, no automática
  - Valida con Jhon ✓

- [ ] **5.3** Bump de versión (propuesta `0.4.0` → `0.5.0`)
  - Archivos: `VERSION`, `setup-team-doctor.sh` (línea `SKALLING_VERSION="0.4.0"`), `install-global.sh`, `setup.sh` y demás scripts que llevan el número hardcodeado (verificarlos con `grep -r "0.4.0" --include="*.sh"`)
  - Reemplazar `0.4.0` → `0.5.0` en todos los lugares
  - Test RED: `grep -r "0.5.0" --include="*.sh" .` aparece; `grep -r "0.4.0" --include="*.sh" .` desaparece
  - Valida con Jhon ✓

- [ ] **5.4** CHANGELOG entrada bajo `[Unreleased]`, luego renombrar a `[0.5.0]`
  - Archivo: `CHANGELOG.md`
  - Estructura: `### Added` con bullets para `scripts/skalling-drift.sh` + `tests/skalling-drift.test.sh` + sección informativa del doctor + documentación en `skalling-doctor.md`
  - `### Changed`: nada en esta versión (backward-compatible)
  - `### Security`: nada nuevo
  - Al cerrar (después de que Luz valide), renombrar `## [Unreleased]` → `## [0.5.0] — YYYY-MM-DD` y agregar nuevo `## [Unreleased]` arriba
  - Valida con Pau ✓

- [ ] **5.5** Test de integración del doctor (Escenario 10 spec 03)
  - Test `test_doctor_info_drift_detection` en `tests/skalling-drift.test.sh`
  - Setup: stub global con `scripts/skalling-drift.sh` presente (vía `cp` a `$OPENCODE_DIR/scripts/`)
  - Aserciones: output del doctor contiene `ℹ Drift detection` o `Drift detection`; no contiene `⚠` ni `✗ Drift`; exit 0 normal y `--strict` sin findings propios
  - Valida con Jhon ✓

- [ ] **5.6** Regresión completa
  - Comando: `bash tests/setup.test.sh` + `bash tests/skalling-drift.test.sh` + cualquier otro `tests/*.test.sh` que ya exista
  - Cero regresiones (todos los tests verdes)
  - Cero `bash -n` errors en ningún script
  - Cero uso de `declare -A`/`mapfile`/`readarray` en scripts nuevos
  - Valida con Jhon ✓ (regresión) + Luz ✓ (quality gate)

- [ ] **5.7** Auditoría Luz + archivado Pau
  - Luz corre `bash -n scripts/skalling-drift.sh` + `bash -n tests/skalling-drift.test.sh` + `grep -E "declare -A|mapfile|readarray"` sobre los nuevos archivos (debe ser vacío) + análisis estático manual de path traversal / claims malformados
  - Tras luz PASSED: Pau archiva `.opencode/changes/skalling-drift-detection/` completo a `.opencode/changes/archive/2026-08/skalling-drift-detection/`
  - Pau actualiza `.opencode/context/log.md` con la entrada de archivado
  - Valida con Luz ✓ + Pau ✓

---

## Estimación

| Fase | Tareas | Tiempo estimado |
|---|---|---|
| 1: Foundation | 6 | ~45 min |
| 2: Verificadores | 8 | ~1h |
| 3: Validación entrada | 4 | ~30 min |
| 4: Robustez | 5 | ~30 min |
| 5: Release | 7 | ~45 min |
| **Total** | **30** | **~3.5h** |

---

## Reglas de ejecución

1. **TDD obligatorio**: cada tarea de implementación tiene RED primero (test que falla), GREEN después (código mínimo), REFACTOR al final.
2. **R2 — cero comentarios**: el código de `scripts/skalling-drift.sh` y `tests/skalling-drift.test.sh` no tiene ni banners descriptivos ni comentarios inline. La claridad viene de identificadores y tests.
3. **R1 — español**: funciones, variables, constantes y mensajes al usuario en español. `verificar_archivo`, no `verify_file`. Excepción: el nombre externo del script (`skalling-drift.sh`) conserva "drift" por convención del problema.
4. **R16 — commits en español**: mensajes propuestos pero NO commiteados sin permiso explícito del usuario. Formato: `<tipo>: <qué>`. Tipos válidos: `feat`, `fix`, `refactor`, `docs`, `test`, `chore`. Presentación previa: scope (archivos a tocar) → espera "ok" → commit.
5. **Bash 3.2 portable**: prohibido `declare -A`, `mapfile`, `readarray`. Globs OK, `[[ =~ ]]` OK, arrays indexados OK.
6. **Tests con cleanup**: `trap 'rm -rf "$FIXTURE"' EXIT` en línea 8, antes de cualquier operación.
7. **Valida con Jhon por tarea**: no acumular cambios entre check-points. Si una tarea falla, fixear antes de avanzar.
8. **Patrón de tests sin comentarios**: copiar estructura de `tests/setup.test.sh` (helpers, contadores, traps, `--verbose`) **pero suprimir todos sus comentarios descriptivos** (los de `# ────── ──` headers y los inline). El spec 03 MUST 3 lo exige.
9. **Sin scripts de un solo uso**: si una tarea pide algo de 5 líneas que cabe inline, no crear archivo nuevo. YAGNI/R14.
10. **Ayudas externas prohibidas**: no usamos `shellcheck` como gate (puede que no esté instalado en todos lados), aunque es buena práctica tenerlo localmente. Validamos con `bash -n` + tests.

---

## Defaults propuestos por Sol (registrados en `design.md`)

Los siguientes huecos de las specs no estaban cerrados. Sol propone lo siguiente y los ha registrado como ADRs — quedan abiertos a override del usuario antes de Fase 1.

| Hueco | Default propuesto |
|---|---|
| Bump de versión | `0.4.0` → `0.5.0` (minor, feature aditiva) |
| Orden de specs | Lexicográfico (`find … \| sort`) |
| `count` cuenta archivos ocultos | **Sí**, comportamiento literal de la spec |
| Activación de colores | Solo si TTY (`[[ -t 1 ]] && [[ -t 2 ]]`) |
| Identificadores de color | `c_verde`, `c_rojo`, `c_azul`, `c_neutro` (español, diverge del patrón repo) |
| Integración doctor | 1 línea `info` al final de `check_project_install()` (no nueva sección) |
| Match de heading | Exacto: `[[ "$linea" = "## Verificación" ]]` |
| Match de fin de bloque | `[[ "$linea" == "## "* ]]` |
| Indentación de bullet | Estricto col-1 (sin tab/espacio antes de `- `) |
| Validación de path | Split por `/`, rechaza segmento `..`, rechaza vacío, rechaza con espacios |
| Fixture strategy | `cp scripts/skalling-drift.sh $FIXTURE/scripts/`, test invoca `bash $FIXTURE/scripts/skalling-drift.sh` |
