# Spec 03: Tests Bash e integración informativa en doctor

> **Status**: Draft
> **RFC 2119 keywords**: MUST / SHALL / SHOULD / MAY
> **Format**: Given/When/Then

## Escenario 1: Estructura del test

**Given** el script `scripts/skalling-drift.sh`
**When** se agrega su suite
**Then** MUST existir `tests/skalling-drift.test.sh`
**And** MUST usar `#!/usr/bin/env bash` y `set -euo pipefail`
**And** MUST resolver `REPO_ROOT` desde `BASH_SOURCE[0]`
**And** MUST usar contadores `PASS` y `FAIL`, helpers `pass`, `fail` y `log`, y soporte `--verbose` conforme al patrón de `tests/setup.test.sh`
**And** MUST terminar con exit code `1` cuando haya al menos un test fallido y `0` en caso contrario.

El test no debe contener comentarios dentro de su código, en cumplimiento de R2. Se conserva la estructura funcional del patrón del repo sin copiar sus comentarios descriptivos.

---

## Escenario 2: Fixtures temporales y cleanup

**Given** que los claims se resuelven contra la raíz del repositorio
**When** corre la suite
**Then** MUST crear una fixture temporal autocontenida para simular un repositorio y un plan archivado
**And** MUST copiar o invocar una copia del script desde una estructura equivalente `<fixture>/scripts/skalling-drift.sh`
**And** MUST crear `<fixture>/.opencode/changes/archive/<mes>/<plan>/specs/`
**And** MUST registrar cleanup con `trap 'rm -rf ...' EXIT`
**And** no debe modificar archivos versionados del repositorio.

---

## Escenario 3: Caso exitoso con los tres claims

**Given** una fixture donde existe `agents-base/Alex.md`
**And** el archivo contiene `SINCRONIZADO CON:`
**And** `agents-base/` contiene exactamente la cantidad declarada
**And** la spec declara `archivo`, `count` y `contiene`
**When** se ejecuta el CLI
**Then** el test MUST comprobar exit code `0`
**And** MUST comprobar tres resultados `PASS`
**And** MUST comprobar que el resumen informa cero fallos.

---

## Escenario 4: Caso de drift mixto

**Given** una spec con al menos un claim verdadero y uno falso
**When** se ejecuta el CLI
**Then** el test MUST comprobar exit code `1`
**And** MUST comprobar que aparecen tanto `PASS` como `FAIL`
**And** MUST comprobar que el script continuó después del primer fallo y reportó todos los claims.

---

## Escenario 5: Cobertura por tipo de fallo

La suite MUST cubrir por separado:

1. `archivo`: archivo ausente.
2. `count`: cantidad observada diferente de la esperada.
3. `contiene`: archivo existente sin el texto literal.
4. `contiene`: archivo ausente.

Cada caso MUST verificar el mensaje relevante y exit code `1`.

---

## Escenario 6: Errores de entrada y formato

**Given** invocaciones o specs inválidas
**When** corre la suite
**Then** MUST verificar exit code `1` para:

- invocación sin argumentos;
- plan inexistente;
- plan sin `specs/`;
- `specs/` sin `.md`;
- specs sin claims reconocidos;
- prefijo reconocido con sintaxis inválida;
- path absoluto o con traversal `..`.

La suite SHOULD verificar que cada error se informa por stderr con un mensaje accionable.

---

## Escenario 7: Límites del bloque

**Given** una spec con claims fuera de `## Verificación`, dentro del bloque y después de un nuevo heading `## Otra sección`
**When** se ejecuta el CLI
**Then** el test MUST comprobar que solo se evalúan los claims dentro del bloque
**And** MUST comprobar que texto narrativo y bullets no reconocidos no crean resultados adicionales.

---

## Escenario 8: Portabilidad y sintaxis

**Given** la implementación final
**When** corre la suite
**Then** MUST ejecutar `bash -n scripts/skalling-drift.sh`
**And** MUST verificar que el script no contiene `declare -A`, `mapfile` ni `readarray`
**And** MUST ejecutar el comportamiento real mediante `bash`, sin requerir que el archivo tenga bit ejecutable.

---

## Escenario 9: Sección informativa del doctor

**Given** `setup-team-doctor.sh`
**When** el doctor imprime sus chequeos
**Then** MUST incluir una sección o línea informativa que indique que drift detection está disponible mediante `bash scripts/skalling-drift.sh <plan-archivado>`
**And** MUST usar el helper/estilo de información del doctor, mostrado con `ℹ` azul
**And** no debe incrementar contadores de warnings o errores
**And** no debe ejecutar automáticamente el script sobre planes archivados
**And** no debe cambiar el exit code del doctor.

La información MAY condicionarse a que `scripts/skalling-drift.sh` exista en la instalación inspeccionada. Si no existe, el MVP no exige warning ni error.

---

## Escenario 10: Test de integración del doctor

**Given** una fixture mínima válida para ejecutar el doctor
**When** se prueba la nueva sección
**Then** un test MUST comprobar la presencia de `ℹ` y del texto identificable `Drift detection`
**And** MUST comprobar que el caso informativo por sí solo mantiene exit code `0` tanto en modo normal como en `--strict`
**And** MUST comprobar que no se imprime `⚠` ni `✗` asociado a drift detection.

La cobertura MAY vivir en `tests/skalling-drift.test.sh` para mantener la integración acotada; no se exige crear otro archivo de test.

---

## Reglas MUST

1. Los tests MUST seguir el patrón de `tests/setup.test.sh`: setup de paths, parsing opcional de `--verbose`, contadores, helpers, bloques de test y resumen final.
2. Los tests MUST usar `set -euo pipefail` y cleanup por `trap`.
3. Los tests MUST contener cero comentarios, conforme a R2.
4. Los identificadores propios en tests y producción MUST estar en español, conforme a R1.
5. La suite MUST cubrir los tres tipos de claims tanto en éxito como en fallo relevante.
6. La suite MUST capturar explícitamente status no cero usando `set +e`/`set -e` o una construcción compatible con `set -e`.
7. La integración del doctor MUST ser exclusivamente informativa (`ℹ` azul), no warning, no error y no bloqueante bajo `--strict`.
8. `command/skalling-doctor.md` MUST documentar la nueva sección informativa y aclarar que la ejecución es manual.
9. Los commits del cambio MUST usar mensajes en español conforme a R16.
10. Toda la suite MUST correr con Bash 3.2 y no usar arrays asociativos.

## Reglas SHOULD

1. La suite SHOULD evitar assertions frágiles sobre códigos ANSI completos; debe validar contenido y severidad de manera legible.
2. Cada test SHOULD crear solo los archivos mínimos requeridos para su escenario.
3. Los mensajes de fallo SHOULD incluir output y status observados cuando `--verbose` está activo.
4. La integración SHOULD reutilizar helpers visuales existentes de `setup-team-doctor.sh` en vez de imprimir secuencias ANSI ad hoc.

## Criterios de aceptación

- [ ] `bash tests/skalling-drift.test.sh` termina en `0` con la implementación correcta.
- [ ] La suite cubre PASS total, FAIL mixto y errores de entrada.
- [ ] Las fixtures se eliminan aunque falle un assert.
- [ ] `bash -n scripts/skalling-drift.sh` pasa.
- [ ] No aparecen APIs exclusivas de Bash 4+.
- [ ] El doctor muestra `ℹ Drift detection` y sigue retornando `0` en `--strict` cuando no hay otros findings.
- [ ] `command/skalling-doctor.md` describe el uso manual.
- [ ] El resto de tests del repositorio no presenta regresiones.

## Out of Spec

- Ejecución de drift detection desde el doctor.
- Escaneo de todos los planes archivados.
- CI o git hooks.
- Benchmarks de rendimiento.
- Tests de semántica avanzada o auto-corrección.
- Un framework de testing nuevo distinto del patrón Bash existente.
