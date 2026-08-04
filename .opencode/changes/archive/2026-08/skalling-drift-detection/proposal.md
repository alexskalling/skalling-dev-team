# Proposal: Drift detection para specs archivadas

> **Status**: Approved
> **Author**: Pol
> **Created**: 2026-08-04
> **Approved**: 2026-08-04 (scope confirmado por el usuario)

## Why

Las specs archivadas hoy funcionan como registro histórico, pero no expresan si sus afirmaciones siguen siendo ciertas. Después de meses de cambios, una spec puede afirmar que existe un archivo, que hay una cantidad determinada de agentes o que un snippet está presente cuando el repositorio actual ya no cumple esas condiciones.

Ese drift convierte la documentación en información engañosa. El problema no termina en el archivo viejo: Pol y Sol pueden usar esas specs como contexto para propuestas y planes nuevos, propagando información podrida hacia decisiones e implementaciones futuras.

Skalling necesita una comprobación pequeña, explícita y repetible que contraste claims simples de un plan archivado contra el estado actual del repositorio. El MVP prioriza checks deterministas que Bash puede verificar sin intentar comprender semántica ni corregir documentos.

## What Changes

Se incorpora un MVP de drift detection compuesto por:

1. Un CLI Bash en `scripts/skalling-drift.sh` que recibe el path de un plan archivado.
2. Lectura de todos los archivos `.md` ubicados directamente en el directorio `specs/` del plan.
3. Extracción de claims declarados en una sección `## Verificación` mediante tres formatos cerrados:
   - `- archivo: <ruta>` para comprobar existencia.
   - `- count: <N> <nombre> en <ruta>` para contar archivos en un directorio.
   - `- contiene: "<texto>" en <ruta>` para buscar texto literal en un archivo.
4. Verificación de cada claim contra el filesystem del repositorio actual.
5. Reporte de una línea `PASS` o `FAIL` por claim, seguido de un resumen.
6. Exit code `0` cuando todos los claims reconocidos pasan y `1` cuando falla cualquier claim o la entrada no puede validarse.
7. Tests Bash con fixtures temporales que cubren los tres tipos de claim, resultados mixtos, errores de entrada y exit codes.
8. Una sección informativa y no bloqueante en `setup-team-doctor.sh` que comunica la disponibilidad del comando; el doctor no ejecuta automáticamente drift detection ni convierte drift en warning/error.

La solución será portable con Bash 3.2, sin arrays asociativos ni dependencias externas aparte de utilidades POSIX ya usadas por el repositorio (`find`, `grep`, `wc`, `sed`). Los identificadores propios y mensajes de commit estarán en español.

## Impact

Archivos previstos:

- `scripts/skalling-drift.sh` — nuevo CLI de extracción, verificación y reporte.
- `tests/skalling-drift.test.sh` — tests Bash siguiendo la estructura y helpers de `tests/setup.test.sh`, con `set -euo pipefail` y cleanup por `trap`.
- `setup-team-doctor.sh` — nueva sección informativa `ℹ` sobre drift detection, sin afectar contadores ni exit code.
- `command/skalling-doctor.md` — documentación de la sección informativa.

No se requieren cambios de schema, migraciones de datos, servicios, hooks ni dependencias de runtime adicionales.

## Out of Scope

Este cambio no incluye:

- Sincronización bidireccional entre specs y código al estilo Open Spec completo.
- Corrección, reescritura o actualización automática de specs con drift.
- Evaluación semántica de si una spec describe correctamente el comportamiento.
- Claims relacionales o complejos, por ejemplo «la función X llama a Y».
- Inferencia libre de claims desde prosa arbitraria fuera de `## Verificación`.
- Integración con git hooks, CI obligatoria o ejecución automática al archivar.
- UI, TUI, API HTTP o servidor.
- Ejecución automática de todos los planes archivados desde el doctor.
- Conversión de findings de drift en warnings o errores del doctor.

## Success Criteria

- Un plan con claims válidos de archivo, count y contiene produce un `PASS` por claim y exit code `0`.
- Si al menos un claim ya no coincide con el repositorio, se reporta `FAIL` para ese claim y el proceso termina con exit code `1`.
- El parser ignora contenido fuera de la sección `## Verificación` y no intenta interpretar lenguaje natural abierto.
- El script corre con Bash 3.2 y no usa `declare -A` ni sintaxis exclusiva de Bash 4+.
- Los tests crean y limpian fixtures temporales, cubren éxito y fallo, y siguen el patrón del repositorio.
- El doctor muestra la disponibilidad del chequeo con severidad informativa `ℹ` azul y no modifica su exit code por drift.

## Dependencies

- **Bloqueado por**: nada.
- **Dependencias externas**: ninguna nueva.
- **Compatibilidad mínima**: Bash 3.2 y utilidades estándar del entorno Unix del proyecto.
