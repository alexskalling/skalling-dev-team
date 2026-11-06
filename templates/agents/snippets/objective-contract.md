## Objetivo y evidencia

TeamDB conserva intent/outcomes/acceptance/files y constraints/non_goals de start;
supersedes mantiene límites. Handoff: id, foco, evidencia. Sin id: `resume {}`;
comparar candidatos con el pedido antes de status. Memoria no concede permisos.
Revisar aceptación/riesgos del cambio. Opcionales: `defer {id,note_id,suggestion,reason}`,
sin bloquear ni implementar.
Aprobar con coverage [{outcome_id,check_index,observation}] y checks propios del
candidato; verde genérico no basta. Cumplido el pedido, cerrar.
Para cambios de transformación o reconstrucción de datos/texto, Teo y Jhon contrastan
entrada con salida COMPLETA esperada: orden, separadores, prefijo/sufijo y contenido
no afectado. Cubrir éxito y fallback, caso único y múltiple cuando existan esas ramas.
Contadores, includes o tests verdes no sustituyen esa comparación. Una regresión debe
detectar el defecto anterior. En cambios de copy/layout, comprobar únicamente el
resultado solicitado y sus efectos relevantes; no abrir una batería por esta regla.
Jhon y Luz fijan review_plan en oracle o su primer check/reuse; el motor crea uno
mínimo si se omite. Con evidencia suficiente, emitir veredicto. Otra comprobación
requiere gap concreto; las inspecciones idénticas se reutilizan sin repetir Git ni
leer node_modules. No delegar de nuevo ni pedir confirmación para un paso ya autorizado.
Completar las fases propias del rol en la misma delegación: revisar, emitir veredicto
y crear el commit si corresponde según commit_policy. No volver a Alex entre esos
pasos ni consultar status si la respuesta recién recibida ya aporta estado vigente.
context_seen solo con cuerpos vigentes presentes; ampliar restricciones de omitted
y contrastar freshness stale/unknown/pending_review. Otro objetivo: otro workflow.

## Contexto y cambios declarativos

TeamDB guarda el foco; la conversación completa no es una cápsula de trabajo.
En cada delegación pasar sólo id, objetivo, restricciones, archivos y evidencia
pertinente. Después de compactar recuperar el workflow vigente, sin crear otro ni
repetir verificaciones válidas. Conservar autorizaciones humanas aún no registradas.

Para copy, iconos u orden declarativo local y reversible, sin alterar lógica,
permisos, datos persistidos, rutas, contratos o accesibilidad: leer lo afectado, editar y
comprobar el resultado completo mediante diff/inspección. No cargar por rutina
TDD, Ponytail ni skills de arquitectura, ni crear tests temporales que reproduzcan
la edición. Esta excepción acota strict_tdd a cambios de comportamiento; no lo
apaga. Si existe lógica, un bug funcional o riesgo, usar la prueba conductual
pertinente. Conservar la revisión asignada por el motor; no ampliar el proceso.

## Resolver bloqueos sin perder el pedido

Mantener el resultado final del usuario en cada handoff: una propuesta, revisión o
commit local no demuestra publicación. Si pidió push, verificar el remoto tras hacerlo.
Antes de afirmar «bloqueado», identificar operación, error observado, condición pendiente
y acción concreta del rol autorizado; una explicación anterior no es evidencia.
recover admite user_instruction con el texto real de la instrucción y feedback_id:
registra feedback y recuperación en una sola operación atómica. Usar continuation:true
si la recuperación inicial está consumida. No pedir al usuario los campos del motor.
Un error de herramienta/verificación se repara sobre la entrega vigente con
replacement_of/retry_of; no enviarlo a Teo como defecto ni consumir otra entrega.
Una nueva instrucción humana obliga a reconciliar restricciones del encargo anterior:
usar focus_revision con supersedes cuando aún hay entregas; en blocked, feedback
correction/scope_change y recover con feedback_id, evidence y recovery_plan. Reutilizar
la autorización ya dada, sin pedirla otra vez. No inferir que «arregla» revoca límites
ajenos al bloqueo. La recuperación inicial permite una entrega adicional. Si se agota
y el usuario vuelve a ordenar continuar, registrar esa instrucción NUEVA con su propio
feedback_id después del bloqueo y usar recover con continuation:true y recovery_plan
concreto. Cada autorización nueva concede una entrega, sin borrar historia, aprobar
hallazgos ni reiniciar presupuestos del usuario. No pedir nuevamente esa autorización
si ya está en la conversación; tampoco inventarla ni reciclar una autorización gastada.
Un error de Git no equivale a estado blocked: en verification_ready se continúa
la revisión vigente. recover sólo reabre un presupuesto de entregas agotado.
No añadir hooks globales al alcance de una aplicación para arreglar Skalling;
identificar la ruta del hook y actualizar la instalación correspondiente.
Un rechazo por estado no prueba que la sesión use una versión antigua.
Pau puede registrar memoria autorizada mediante teamdb-memory.sh antes de la revisión;
action document sólo cierra la etapa documental. Verificar la fila real, no sólo el JSON.
Hallazgos ajenos al pedido van a defer; no descartar una prueba fallida pertinente ni
aprobar sin evidencia. Si queda un impedimento, explicar exactamente qué debe cambiar.
