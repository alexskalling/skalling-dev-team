---
name: skalling-handoff
description: Contratos de entrega entre agentes con evidencia completa y referencias a TeamDB.
---

# Handoff

Usar templates/handoff.schema.json como contrato canónico. No crear archivos JSON
temporales: transmitir el objeto al agente receptor.

Siempre incluir from, to, task, summary y next_action.
Para planes conservar plan_id y feature-slug.
Para ingeniería incluir project_context y evidencia verification cuando corresponda.
Toda entrega a Teo incluye readiness, implementation_allowed, route y
request_context con files, acceptance y reuse. Copiar el resultado real del clasificador;
nunca inventar true, aprobación ni evidencia.

initialized significa almacenamiento preparado. La comprensión depende de los
archivos leídos y del pedido. Si una cápsula tiene needs_expansion/omitted, recuperar
las filas completas antes de implementar; una ruta de archivo no equivale a su contenido.

Sol devuelve el plan a Alex para validar routing antes de enviarlo a Teo.
Pol devuelve decisiones pendientes a Alex para el usuario; no responde por él.

## Ejemplo de verificación

```json
{
  "from": "TEO",
  "to": "JHON",
  "task": "Verificar el cambio de validación",
  "summary": "Cambio acotado implementado siguiendo el plan acordado.",
  "plan_id": 1,
  "feature-slug": "validacion",
  "verification": {
    "command": "<comando realmente ejecutado>",
    "exit_code": 0,
    "output_summary": "<resultado observado>"
  },
  "next_action": "Verificar casos positivos y negativos"
}
```

El ejemplo muestra la estructura; sus resultados no son evidencia de una ejecución real.
No omitir criterios o restricciones para respetar un presupuesto arbitrario de tokens.
Si falta contexto, devolver qué falta y continuar las lecturas permitidas.
