---
name: skalling-cycle
description: Flujo de agentes por riesgo, contexto suficiente y consentimiento del usuario.
---

# Ciclo de trabajo

La clasificación canónica vive en skalling-routing. Esta skill explica cómo ejecutar
la ruta elegida; no define atajos alternativos.

1. Alex recupera el pedido completo y la memoria pertinente. Lee archivos conocidos;
   Jes investiga cuando falta evidencia estructural. Tener un índice no significa haberlo consultado.
2. Alex clasifica impacto, riesgo y decisiones pendientes. Comunica el motivo y
   conserva request_id. Sin evidencia suficiente, investiga; no manda a construir.
3. Low local: Teo implementa y Jhon verifica. Cambios visuales usan como mínimo INLINE.
4. Medium: Sol prepara y persiste un plan con aceptación y estrategia de reutilización.
   Devuelve plan_id a Alex, que comprueba el contexto antes de delegar a Teo.
5. High: Pol aclara producto y devuelve el contrato a Alex; no escribe DB ni archivos.
   Alex transmite al usuario las decisiones críticas pendientes. Sol persiste el
   plan acordado; Teo implementa; Jhon verifica regresión y Luz audita riesgos.
6. Pau consolida solo conocimiento durable cuando exista, también en rutas low/medium.
   Ninguna ruta obliga a guardar un resumen rutinario.

## Persistencia

TeamDB conserva proposals, plans, tasks, decisiones y conceptos. Sol usa
teamdb-plan.sh y teamdb-amend.sh. Pau usa teamdb-memory.sh.
El sistema de diseño es concepts/design-system. No se generan carpetas Markdown
para transportar trabajo; las exportaciones se solicitan explícitamente.

## Ejecución y cierre

Teo recibe archivos relevantes leídos, aceptación, reutilización, contexto completo
y el resultado de routing. Para medium/high se exige plan aprobado.
Usa teamdb-claim.sh para reclamar y liberar tareas; Jhon revisa y aprueba; Pau
resuelve tareas cuando corresponde. Consultar --help de los helpers antes de inventar flags.

Si cambia el alcance o aparece una decisión crítica, devolver la evidencia a Alex.
No rebajar el riesgo para evitar un bloqueo. Máximo tres correcciones por tarea;
después explicar el impedimento y la alternativa concreta.

Los handoffs cumplen templates/handoff.schema.json. Las omisiones se explican;
ningún agente debe responder vacío por faltar contexto.

## Publicación

Pruebas aprobadas y plan aprobado no autorizan push/deploy.
Alex conserva y transmite el permiso explícito del usuario para la sesión y el destino.
La revisión del usuario, si la pidió, ocurre antes de publicar.
