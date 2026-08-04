# Spec 03: Tests Bash e integración informativa en doctor

> **Status**: Draft
> **RFC 2119 keywords**: MUST / SHALL / SHOULD / MAY
> **Format**: Given/When/Then

## Escenario 1: Estructura del test

**Given** el script `scripts/spec-memory-link.sh`
**When** se agrega su suite
**Then** MUST existir `tests/spec-memory-link.test.sh`
**And** MUST usar `#!/usr/bin/env bash` y `set -euo pipefail`
**And** MUST resolver `REPO_ROOT` desde `BASH_SOURCE[0]`
**And** MUST usar contadores `PASS` y `FAIL`, helpers `pass`, `fail`, `log`, asserts tipados (`assert_file_exists`, `assert_file_contains`, `assert_file_contains_exact`), y soporte `--verbose` conforme al patrón de `tests/concept-template.test.sh`
**And** MUST terminar con exit code `1` cuando haya al menos un test fallido y `0` en caso contrario.

El test no debe contener comentarios dentro de su código (R2). El patrón funcional se hereda del repositorio sin copiar sus comentarios descriptivos.

---

## Escenario 2: Fixtures temporales y cleanup

**Given** que el script resuelve paths desde la raíz del repositorio
**When** corre la suite
**Then** MUST crear una fixture temporal autocontenida en `$(mktemp -d)` para simular un repositorio con:
  - `<fixture>/.opencode/context/concept/` (vacío o con concept docs de prueba).
  - `<fixture>/.opencode/changes/<plan>/` con `proposal.md`, `design.md`, `tasks.md` y `specs/*.md`.
  - Una copia del script bajo prueba en `<fixture>/scripts/spec-memory-link.sh`.

**And** MUST registrar cleanup con `trap 'rm -rf "$FIXTURE"' EXIT`.

**And** MUST permitir que el script corra sobre la fixture pasando el root del repo simulado por env var, argumento o copia in-place (cualquier variante es aceptable si la suite es determinista y no pisa el repo real).

**And** no debe modificar archivos versionados del repositorio.

---

## Escenario 3: Caso exitoso — múltiples concept docs afectados

**Given** una fixture con `concept/repo-pattern.md` (con las 4 secciones) y `concept/db-schema.md`
**And** un plan con `proposal.md` que menciona ambos paths
**When** se ejecuta el script
**Then** el test MUST comprobar exit code `0`
**And** MUST comprobar que ambos concept docs recibieron el footer `## Spec original`
**And** MUST comprobar que el path del link es relativo y bien formado.

---

## Escenario 4: Sin concept docs afectados

**Given** un plan válido que NO contiene el patrón de búsqueda
**When** se ejecuta el script
**Then** el test MUST comprobar exit code `0`
**And** MUST comprobar que ningún concept doc fue creado ni modificado
**And** MUST comprobar que el output incluye el mensaje informativo `0 concept docs afectados`.

---

## Escenario 5: Idempotencia — segundo run no modifica

**Given** un plan que afecta a `concept/repo-pattern.md`
**And** el primer run del script ya agregó el footer
**When** se ejecuta el script una segunda vez sobre el mismo plan
**Then** el test MUST comprobar que el archivo `concept/repo-pattern.md` no fue modificado (mismo contenido, mismos bytes, mismo `mtime` o comparación por hash).

**And** MUST comprobar que el output del segundo run incluye `preservado:` para ese concept doc.

---

## Escenario 6: Preservar el primero cuando hay footer pre-existente

**Given** un concept doc que ya tiene `## Spec original` con un link a un plan anterior `archive/2026-05/otro-plan/`
**And** un plan nuevo que también referencia ese concept doc
**When** se ejecuta el script con el plan nuevo
**Then** el test MUST comprobar que el footer existente NO fue sobrescrito
**And** MUST comprobar que el link sigue apuntando a `archive/2026-05/otro-plan/`
**And** MUST comprobar que el output incluye `preservado:` para ese concept doc.

---

## Escenario 7: Referencia rota no aplica footer

**Given** un plan que menciona `.opencode/context/concept/inexistente.md` y `.opencode/context/concept/db-schema.md`
**And** solo `db-schema.md` existe en la fixture
**When** se ejecuta el script
**Then** el test MUST comprobar exit code `0` (las advertencias no abortan)
**And** MUST comprobar que `db-schema.md` recibió el footer
**And** MUST comprobar que el output por stderr incluye `advertencia: referencia a concept doc inexistente: .opencode/context/concept/inexistente.md`
**And** MUST comprobar que no se creó ningún archivo `inexistente.md`.

---

## Escenario 8: Concept doc no escribible

**Given** un concept doc que existe pero no es escribible (chmod `a-w` o root-only, según la fixture)
**When** se ejecuta el script
**Then** el test MUST comprobar que el script sigue procesando los demás concept docs
**And** MUST comprobar que el output incluye `error: no se puede escribir <path>`
**And** el exit code final refleja el resultado agregado (no aborta por un único error).

**Nota portable**: `chmod a-w` en directorio temporal puede requerir ser root para revertir; el test debe usar `chmod` con cuidado y posiblemente correr el sub-set de error en una función opt-in. Si esto complica la portabilidad, el test marca este caso como `SKIP` aceptable en macOS donde los permisos se comportan distinto.

---

## Escenario 9: Errores de entrada y formato

**Given** invocaciones o specs inválidas
**When** corre la suite
**Then** MUST verificar exit code `1` para:
  - invocación sin argumentos;
  - invocación con dos o más argumentos;
  - directorio del plan inexistente;
  - directorio del plan sin archivos escaneables (ni `proposal.md`, ni `design.md`, ni `tasks.md`, ni `specs/`).

La suite SHOULD verificar que cada error se informa por stderr con prefijo `error:` y un mensaje accionable.

---

## Escenario 10: Formato exacto del footer

**Given** un concept doc afectado
**When** el script aplica el footer
**Then** el test MUST comprobar que el archivo termina con el bloque exacto (probando las últimas líneas):

```text

## Spec original

[.opencode/changes/archive/<YYYY-MM>/<plan>/](.opencode/changes/archive/<YYYY-MM>/<plan>/)
```

**And** MUST comprobar que el link es relativo al concept doc (para un concept doc en `.opencode/context/concept/`, el path relativo sube dos niveles).

**And** MUST comprobar que el resto del archivo (frontmatter, secciones previas, trailing newline) está intacto.

---

## Escenario 11: Portabilidad y sintaxis

**Given** la implementación final
**When** corre la suite
**Then** MUST ejecutar `bash -n scripts/spec-memory-link.sh`
**And** MUST verificar que el script no contiene `declare -A`, `mapfile` ni `readarray`
**And** MUST verificar que el script usa `#!/usr/bin/env bash` y `set -euo pipefail`
**And** MUST ejecutar el comportamiento real mediante `bash`, sin requerir que el archivo tenga bit ejecutable.

---

## Escenario 12: Sección informativa del doctor

**Given** `setup-team-doctor.sh`
**When** el doctor imprime sus chequeos y existe `scripts/spec-memory-link.sh`
**Then** MUST incluir una línea informativa que indique que el link spec ↔ memory está disponible
**And** MUST usar el helper `info()` del doctor, mostrado con `ℹ` azul
**And** no debe incrementar contadores de warnings ni de errores
**And** no debe ejecutar automáticamente el script
**And** no debe cambiar el exit code del doctor.

El texto informativo MAY ser similar a:

```text
ℹ Spec ↔ Memory link disponible: bash scripts/spec-memory-link.sh <plan-archivado>
```

Si el script no existe, el MVP no exige warning ni error.

---

## Escenario 13: Test de la integración del doctor

**Given** una fixture mínima válida para ejecutar el doctor (siguiendo el patrón de `tests/doctor-memory.test.sh`)
**When** se prueba la nueva sección
**Then** un test MUST comprobar la presencia de `ℹ` y del texto identificable `Spec`
**And** MUST comprobar que el caso informativo por sí solo mantiene exit code `0` tanto en modo normal como en `--strict`
**And** MUST comprobar que no se imprime `⚠` ni `✗` asociado a spec-memory-link.

La cobertura MAY vivir en el mismo `tests/spec-memory-link.test.sh` para mantener la integración acotada; no se exige crear otro archivo de test.

---

## Reglas MUST

1. Los tests MUST seguir el patrón de `tests/concept-template.test.sh`: setup de paths, parsing opcional de `--verbose`, contadores, helpers, bloques de test y resumen final.
2. Los tests MUST usar `set -euo pipefail` y cleanup por `trap`.
3. Los tests MUST contener cero comentarios, conforme a R2.
4. Los identificadores propios en tests y producción MUST estar en español, conforme a R1.
5. La suite MUST cubrir éxito, no-op (sin matches), idempotencia, preservación del primero, referencia rota, errores de entrada y portabilidad.
6. La suite MUST capturar explícitamente status no cero usando `set +e`/`set -e` o una construcción compatible con `set -e`.
7. La integración del doctor MUST ser exclusivamente informativa (`ℹ` azul), no warning, no error y no bloqueante bajo `--strict`.
8. `command/skalling-doctor.md` MUST documentar la nueva línea informativa y aclarar que la ejecución es manual.
9. Los commits del cambio MUST usar mensajes en español conforme a R16.
10. Toda la suite MUST correr con Bash 3.2 y no usar arrays asociativos.

## Reglas SHOULD

1. La suite SHOULD evitar assertions frágiles sobre códigos ANSI completos; debe validar contenido y severidad de manera legible.
2. Cada test SHOULD crear solo los archivos mínimos requeridos para su escenario.
3. Los mensajes de fallo SHOULD incluir output y status observados cuando `--verbose` está activo.
4. La integración SHOULD reutilizar el helper `info()` existente de `setup-team-doctor.sh` en vez de imprimir secuencias ANSI ad hoc.
5. La suite SHOULD usar fixtures autocontenidas en `$(mktemp -d)` y no depender de archivos de test globales.

## Criterios de aceptación

- [ ] `bash tests/spec-memory-link.test.sh` termina en `0` con la implementación correcta.
- [ ] La suite cubre éxito, no-op, idempotencia, preservación del primero, referencia rota y errores de entrada.
- [ ] Las fixtures se eliminan aunque falle un assert.
- [ ] `bash -n scripts/spec-memory-link.sh` pasa.
- [ ] No aparecen APIs exclusivas de Bash 4+.
- [ ] El doctor muestra `ℹ Spec` y sigue retornando `0` en `--strict` cuando no hay otros findings.
- [ ] `command/skalling-doctor.md` describe la disponibilidad del script.
- [ ] El resto de tests del repositorio no presenta regresiones.

## Out of Spec

- Ejecución automática del script desde el doctor.
- Conversión de findings en warnings o errores.
- CI o git hooks.
- Benchmarks de rendimiento.
- Tests de semántica avanzada o auto-corrección.
- Un framework de testing nuevo distinto del patrón Bash existente.

## Verificación

```markdown
## Verificación

- archivo: tests/spec-memory-link.test.sh
- archivo: setup-team-doctor.sh
- contiene: "Spec" en setup-team-doctor.sh
- contiene: "spec-memory-link" en command/skalling-doctor.md
- count: 3 specs en .opencode/changes/spec-memory-link/specs
```
