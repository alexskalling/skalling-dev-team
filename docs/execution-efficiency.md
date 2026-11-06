# Ejecución con menos espera

`skalling-execution-efficiency` aplica un contrato breve antes de cada llamada
al modelo exclusivamente para Alex, Pol, Sol, Teo, Jhon, Luz, Jes y Pau.
Build, Plan, General y cualquier otro agente conservan su contexto original y
sus comandos no se observan. No requiere TeamDB ni
un workflow. El instalador lo distribuye junto con los demás plugins.

Prioriza agrupar consultas independientes, guardar y reutilizar logs de pruebas,
preservar el código de salida, verificar los archivos afectados y consultar CI
antes de esperar. Conserva las verificaciones finales requeridas y distingue
commit, push y despliegue. El push sigue requiriendo autorización aplicable.

## Revisiones proporcionales y recuperables

La revisión ahora fija un plan por revisor, tanto Jhon como Luz. Se declara en el
oráculo o en el primer check/reuse; si falta, el motor congela el primer criterio
como plan mínimo sin añadir una llamada de planificación. Una ampliación requiere
gap concreto. Todos los criterios del plan propio deben estar cubiertos para aprobar.
La aprobación sigue siendo independiente de que una inspección sea reutilizada.

La inspección nativa identifica sus entradas cerradas: archivos solicitados,
contenido, commit base, versión de Python y código del motor. No recorre dependencias
ni caduca por tiempo; cambios ajenos no invalidan ese diff. Otro revisor puede
reutilizar el mismo resultado sin repetir Git, conservando su juicio independiente.
Los comandos arbitrarios mantienen la validación conservadora del workspace y
vigencia: no se presume que sólo lean los archivos declarados.

Medición local de lectura en actas3.0.0, 2026-11-06, para el diff de
`src/app/precios/mi-primer-acta-gratis/page.tsx`: tres muestras del control anterior
6006,854 / 2297,978 / 2289,495 ms; control acotado 0,842 / 0,349 / 0,334 ms.
Medianas: 2297,978 ms y 0,349 ms. Es tiempo de validación de caché, no velocidad
del modelo ni duración de una tarea completa; los archivos del proyecto no se modificaron.

`review_timing` separa tiempo de comando y validación de caché por entrega y marca
los registros antiguos que no tenían esa separación. Los tokens de ventanas de
sesiones se identifican como estimaciones no sumables entre workflows: no son una
contabilidad exacta por tarea cuando comparten sesiones.

Cada respuesta del plugin identifica la ruta y SHA del backend, el plugin cargado,
su versión en disco y el contrato de herramienta cargado. `reload_required` detecta
código viejo en memoria. El prompt completo del agente no es observable por esta
interfaz: no se presenta un archivo leído de disco como prueba de un prompt cargado.

`recover` admite `user_instruction` y `feedback_id` junto al diagnóstico y plan:
feedback y recuperación se registran en una única transacción. Un fallo revierte
ambos; repetir la misma solicitud no concede otra entrega. La instrucción debe
ser real, no inferida ni inventada. Los rechazos clasificados como infraestructura
se dirigen a reparar el check sobre la entrega vigente, sin consumir otra entrega.

Regresiones: `verification-efficiency.test.py`, `workflow-recovery.test.py` y
`workflow-plugin.test.mjs`; el paquete instalado ejecuta también las dos primeras.
Esta unidad se revierte retirando los helpers de caché/plan, metadatos del plugin
y sus instrucciones/pruebas; no requiere eliminar TeamDB ni registros previos.

`probe` y `check configured:true` seleccionan únicamente `testing.fast` por
defecto. Si sólo existe `testing.unit`, no ofrecen ni ejecutan esa suite como
baseline automático. Ejecutarla deliberadamente requiere `profile:"unit"` e
`impact_reason` ligado al cambio; el comando sigue congelado desde `start`.
Esto también se aplica a workflows anteriores que guardaron el fallback unit.

Jhon declara `review_plan:["criterio", ...]` en el oráculo y usa esos textos
en `check.criterion`. Al cubrirlo, el motor recomienda evaluar `coverage` y
aprobar. Una comprobación repetida o fuera del plan exige `gap`: una carencia
concreta de evidencia. Un plan incompleto no puede aprobarse. Los workflows
antiguos sin plan conservan su evidencia y no requieren reiniciar la entrega.
El motor comprueba la estructura; el revisor sigue juzgando si la prueba es
pertinente y si todos los resultados pedidos están demostrados.

`check inspection:{kind:"diff"|"file",files:[...]}` ofrece lectura del candidato
y su base Git sin shell arbitrario, filtros externos ni Node con subprocess.
Sólo admite archivos del alcance, rechaza enlaces simbólicos y limita el tamaño.
Incluye archivos nuevos y eliminados; `file` devuelve antes/después. La salida
abreviada indica si está truncada; `evidence` recupera el registro completo.
Un diff leído no demuestra por sí solo comportamiento o apariencia visual.

Un comando defectuoso se corrige con `replacement_of:N`, el mismo `criterion`,
`failure_kind:"invalid_check"|"infrastructure"` y `evidence` concreta. Para
repetir el mismo comando se conserva `retry_of`. Comparten dos reparaciones por
entrega, se validan antes de ejecutar y sólo un resultado exitoso sustituye el
fallo; la historia permanece en TeamDB. No requieren redeliver ni consumen otra
entrega. Un defecto real, un fallo de otro revisor o un criterio diferente no
se resuelven por esta vía. La clasificación semántica sigue siendo responsabilidad
del revisor; no equivale a una prueba automática de ausencia de defectos.

Las comprobaciones deterministas locales con `reusable:true` también se pueden
reutilizar al retomar en otra sesión del mismo revisor, conservando las validaciones
de candidato, entorno, workspace y vigencia. Nunca se reutilizan resultados de
entradas externas por declararlos arbitrariamente locales.

`tests/verification-efficiency.test.py` reproduce el movimiento de secciones
observado en actas3.0.0 (f2833ca), el fallo del verificador y la configuración sin
fast. Corre también contra el paquete instalado. Mide el flujo mecánico, no la
latencia ni los tokens de una conversación futura con modelos.

## Foco recuperable en TeamDB

`skalling_workflow start` conserva `intent`, `outcomes`, `acceptance`, archivos y
evidencia en `agent_workflows`. También acepta `constraints` y `non_goals`: hasta
12 textos de 500 caracteres por lista, 4 KB combinados. Son límites explícitos
del pedido, no inferidos. `supersedes` conserva los anteriores y agrega nuevos;
no elimina restricciones por omisión. Un cambio explícito del usuario puede
reemplazarlas mediante `focus_revision: {feedback_id,evidence}`: sólo se reemplazan
las listas incluidas, las demás se heredan. El workflow anterior conserva los
límites originales y el nuevo empieza sin cobertura ni pruebas aprobadas; no
reinicia el presupuesto de entregas. La evidencia es declarada por el agente,
no una autenticación independiente del mensaje humano. Las respuestas identifican
su fuente con `memory_source`. No se agrega otra base ni un archivo de memoria.

Si falta el id tras reiniciar o compactar, `resume` con `{}` consulta TeamDB en
modo lectura. Recupera el único workflow activo asociado a la sesión del runtime
y al checkout. Si falta esa asociación o hay varios, devuelve hasta ocho
candidatos con `more_candidates`; se compara el pedido antes de consultar
`status` por id. No inicia tareas, migra bases ni atribuye autorización a la memoria.
Sin base devuelve `missing`; una base ilegible produce un error, no memoria inventada.

Las mejoras opcionales van a `defer {id,note_id,suggestion,reason}` durante la
revisión. Hasta 12 notas, idempotentes por rol e id, permanecen en TeamDB sin
rechazar, aprobar, ampliar alcance ni invalidar evidencia. `reject` rechaza
hallazgos explícitamente no bloqueantes; `outcome_id`, cuando se aporta, debe
pertenecer al pedido. Un riesgo de seguridad pertinente sigue siendo bloqueante.
Los diagnósticos antiguos sin referencia conservan compatibilidad: el motor
valida identidad y forma, no puede demostrar la pertinencia semántica del texto.

El contrato compartido exige justificar revisiones con resultados o riesgos del
cambio, conservar evidencia vigente y cerrar al cumplir el pedido. No instala
límites arbitrarios de tokens ni promete ahorro medido. El límite existente de
tres entregas normales y los revisores exigidos por riesgo siguen vigentes.

### Recuperación de un proceso bloqueado

Tras tres rechazos, `recommended_action` indica `recover`, no un `supersedes`
que fallaría por el mismo presupuesto. Alex registra `feedback` de tipo
`correction` o `scope_change` con la instrucción humana existente y ejecuta
`recover {id,feedback_id,evidence,recovery_plan}`. No necesita pedir de nuevo una
autorización ya recibida. La evidencia identifica el bloqueo y el plan indica
qué operación lo resuelve. La recuperación inicial por cadena habilita una entrega
adicional; conserva hallazgos, diagnósticos, riesgo, objetivo y límites explícitos
de recursos. No fabrica aprobaciones ni reutiliza checks como si fueran nuevos.

`constraints`, `non_goals` y `commit_policy` pueden actualizarse sólo conforme a
ese feedback; omitirlos conserva sus valores. El motor valida la referencia al
feedback, pero el agente sigue siendo responsable de representar fielmente la
instrucción humana. Reintentar el mismo payload es idempotente. `supersedes` hereda
la recuperación usada. Si vuelve a fallar, informa la operación, el error y la
acción pendiente; no inicia otra ronda automáticamente. Si el usuario vuelve a ordenar
continuar, Alex registra esa instrucción nueva después del bloqueo y llama a
`recover {id,continuation:true,feedback_id,evidence,recovery_plan}`. Cada autorización
nueva concede una entrega adicional en el mismo workflow. El motor rechaza feedback
anterior al bloqueo, gastado o de otro tipo; el agente debe representar fielmente la
instrucción humana. `authorized_continuations` conserva las concesiones y `supersedes`
las hereda junto al contador. Repetir un payload no concede otra entrega. Presupuestos
explícitos de checks/tiempo, hallazgos y revisores no se eliminan. Esta unidad se puede
retirar junto con sus instrucciones y pruebas, conservando los registros de TeamDB.

Pau registra memoria autorizada con `teamdb-memory.sh`; `document` es el cierre
posterior a la revisión. Una fila necesaria para verificar una entrega puede
persistirse antes de aprobarla. El error del hook identifica tabla, slug y helper;
no basta con mostrar el JSON candidato. El push se acredita con Git/remoto, no
con la finalización del workflow.

Los `index.md` raíz de las colecciones de decisiones, problemas, followups y
changes son navegación: el hook no exige filas llamadas `index`. Sus controles
de secretos y privacidad siguen activos, igual que la comprobación de filas para
decisiones reales. Un fallo del hook no cambia el estado del motor a `blocked`:
si continúa en `verification_ready`, se resuelve el fallo externo y se sigue
la revisión existente. Los hooks globales se corrigen en Skalling, fuera del
alcance de archivos de la aplicación.

Antes de un push, el hook consulta una vez las referencias actuales del destino
con `git ls-remote`. Revisa los commits nuevos respecto de ese historial publicado,
incluidas las ramas laterales de merges, y no exige receipts retroactivos para
commits que ya están allí. No confía en referencias locales `origin/*` para
eximir cambios. Si la consulta falla, informa el problema de conectividad y
detiene la comprobación; no omite revisiones. Sin destino explícito, usa sólo
el SHA remoto recibido en la entrada del hook como base conocida.

Regresión de fuente y paquete instalado: `python3 tests/workflow-recovery.test.py`
y `python3 tests/installed-workflow.test.py`. La unidad de recuperación comprende
el motor, contrato del plugin, instrucciones de agentes y diagnóstico del hook;
se puede retirar en conjunto sin borrar TeamDB. `process_recovery` es un campo
JSON aditivo: no requiere migración de datos.

El complemento observa comandos repetidos, salidas filtradas y esperas largas
y añade recordatorios concretos al siguiente contexto. Conserva solamente
hashes de los últimos 32 comandos por sesión, hasta 64 sesiones, sin guardar
salida ni texto de comandos. No hace consultas a disco, red, base de datos ni
modelos en sus hooks; no modifica ni ejecuta comandos y no añade gates.

Esto orienta al modelo: no garantiza que obedezca ni representa una reducción
de latencia ya medida. No reutiliza automáticamente resultados, porque no puede
demostrar que código, dependencias y entorno siguen iguales. Una repetición
observada no se clasifica automáticamente como desperdicio.

El plugin se distribuye únicamente como paquete en
`plugins/skalling-execution-efficiency/`, con `index.js` y `package.json`.
La implementación compartida está en `plugins/lib/execution-efficiency.mjs`.
OpenCode lo descubre automáticamente; la configuración del proyecto también
puede referenciar ese mismo paquete. No se distribuye un segundo entrypoint
`.js` en la raíz de `plugins`: OpenCode descubría ambos y mostraba una entrada
fallida. Al actualizar se retira ese archivo antiguo después del respaldo.
El inventario rechaza una instalación que todavía lo contenga, aunque haya sido
registrada. La prueba con OpenCode real exige una sola carga y una sola cápsula.
Solo actúa sobre los ocho agentes de Skalling; las sesiones abiertas pueden
necesitar reiniciar OpenCode para cargar los cambios.

Validación focal: `node --test tests/execution-efficiency.test.mjs`.
Persistencia y recuperación: `python3 tests/workflow-engine.test.py`.
Sincronización y fixtures usan `agents-base` con el renderer canónico, sin
depender de `.opencode/agents` generado; preservan las cabeceras personalizadas
y respaldan los cuerpos antes de una sincronización explícita.
Prueba con OpenCode real y proveedor sintético local:
`python3 tests/runtime/execution-efficiency-smoke.py` (sin modelo de pago).
Retirada: quitar la entrada de configuración y los cuatro archivos del plugin.

La recuperación y notas son una unidad independiente del plugin: retirarlas
requiere revertir el motor, `skalling_review_cycle.py`, su descripción de herramienta
y el contrato compartido. No necesita borrar ni migrar TeamDB; los campos JSON
aditivos permanecen como historial. La sincronización de agentes y preparación
de evaluaciones pueden conservarse independientemente.

## Cierre, recursos y evaluación

`start.commit_policy` admite `allowed` (por defecto), `required` y `forbidden`.
`allowed` permite completar la entrega sin commit; `required` exige uno si hay
cambios; `forbidden` rechaza `prepare_commit` y `commit`, también tras completar.
El cierre conserva el índice del usuario. Con `forbidden` no sella una autorización
de commit. La política se hereda en `supersedes`; cambiarla exige `focus_revision`.
Workflows antiguos sin el campo conservan la política requerida por compatibilidad.
Esto controla el motor; no impide al propietario del sistema ejecutar Git directamente.

Los comandos de verificación drenan stdout/stderr durante la ejecución y retienen
los últimos 16.000 bytes, sin acumular el log completo. Conservan el timeout y la
cancelación del grupo de procesos. La prueba de regresión emite 32 MiB y exige que
las asignaciones Python del lector permanezcan por debajo de 2 MiB; no mide la
memoria del proceso de pruebas ni implica un ahorro de tokens del modelo.

El inventario de instalación registra una huella de las fuentes del runtime,
plantillas y agentes. `skalling-runtime.py check` detecta fuentes distintas aunque
VERSION siga igual. Un inventario antiguo sin huella informa que no puede confirmar
la correspondencia: requiere actualizar la instalación. La huella no lee TeamDB.
La identidad de la instalación no prueba qué código mantiene cargado una sesión;
se debe reiniciar OpenCode tras actualizar sus plugins.

`tests/evals/tasks.json` contiene seis escenarios: casos límite, Unicode, aislamiento
de datos anidados, rollback SQLite y configuración entre módulos. El evaluador
comprueba el comportamiento, alcance, cierre y que HEAD no cambie cuando se pide
sin commit. Comparar una ejecución contra `--baseline` sigue siendo descriptivo:
no demuestra causalidad ni superioridad sobre un agente individual. Las pruebas
unitarias del evaluador no ejecutan modelos ni acreditan competencia del equipo.

Validación de estas correcciones: motor, review-cycle, agent-outcomes,
runtime-identity, comandos e instalación aislada. La unidad de cierre/foco se
revierte con motor, review_cycle, prompts, descripción de herramienta y pruebas;
el lector acotado y la huella de instalación pueden revertirse por separado.
Ninguna retirada exige borrar TeamDB o los campos históricos ya guardados.

## Persistencia y recuperación del foco

La conexión compartida `skalling_db.connect` activa claves foráneas en cada
conexión y usa el timeout de SQLite. Los lectores abren `mode=ro` y `query_only`;
los escritores operativos abren `mode=rw`, sin crear bases por accidente.
Sólo inicialización y los helpers con creación explícita usan `create=True`.
WAL se establece al inicializar, no en cada consulta. `teamdb_guard` conserva
sus autorizaciones y el historial de conocimiento durable sobre esta conexión.

La migración idempotente `066_workflow_projection.py` añade columnas virtuales
para estado, proyecto, sesión inicial y revisión, además de índices de recuperación.
Se derivan del JSON existente: no hay dos estados editables ni se reescribe el
historial. Si encuentra JSON inválido, revierte toda la migración y falla; no borra
ni interpreta silenciosamente esos registros. `teamdb-init.sh` la aplica a bases
existentes; las nuevas incluyen la misma estructura en el esquema base.

`save` persiste estado y eventos sin consultar la base de OpenCode. El consumo se
recoge después del cierre/cancelación/fallo y al reemplazar un pedido, fuera del
bloqueo de escritura, y se guarda en `workflow_metrics`. Una condición sobre la
revisión impide que una medición atrasada actualice una revisión distinta.
`status` puede consultar consumo vigente sin reescribir el estado. Si la medición
falla, la entrega sigue cerrada y el consumo desconocido no se inventa.

`intent`, `outcomes`, `acceptance`, `constraints`, `non_goals` y `commit_policy`
salen directamente del workflow en start/status/resume. No compiten por un puesto
en el ranking de memoria ni se duplican dentro de otra cápsula. Si falla una
consulta de memoria opcional, se entrega el foco y se marca esa consulta como
`unavailable`. Las decisiones históricas siguen siendo contexto, no autorización.

La búsqueda habitual reutiliza `concepts_fts`, `decisions_fts` y `problems_fts` ya
existentes. Los tokens se citan como datos; slugs y referencias a archivos mantienen
búsqueda literal. Preferencias y bases sin esos índices conservan la ruta léxica.
Las decisiones reemplazadas/rechazadas no se recuperan como vigentes. FTS5 mejora
coincidencias de palabras y tildes, no resuelve sinónimos ni contradicciones por sí solo.
`python3 tests/evals/retrieval.py` compara seis consultas reproducibles: en la
validación local, léxico recuperó 2/6 y FTS5 6/6 dentro de los primeros tres resultados.
Este conjunto pequeño no demuestra velocidad ni calidad semántica general.

## Medir antes de añadir participantes

Un pedido local y claro sin planificación, task o memoria pendiente inicia directo
incluso si su riesgo exige Jhon y Luz. Ambos revisores siguen siendo obligatorios
para riesgo alto. `staged`, planes existentes y trabajo pendiente conservan sus
requisitos; no se agrega Pol/Sol/Pau únicamente por la etiqueta de riesgo.

El evaluador admite `--mode single` (Build sin delegación) y `--mode team` (Alex),
`--model proveedor/modelo` y `--repeat N`. Ambos modos exigen comportamiento correcto,
alcance y respeto de la prohibición de commit; el equipo además debe cerrar su
workflow. Los tokens provienen del registro del runtime, nunca del tamaño del texto;
si no se identifica la sesión o faltan mediciones, quedan desconocidos. Se informa
el tiempo de ejecución del agente separado del tiempo total de preparación.

Ejemplo de comparación, que ejecuta modelos reales y consume sus recursos:

```sh
python3 tests/evals/run.py --mode single --model proveedor/modelo --repeat 3 --output /tmp/single.json
python3 tests/evals/run.py --mode team --model proveedor/modelo --repeat 3 --baseline /tmp/single.json --output /tmp/team.json
```

El resultado empareja tarea y repetición. Que coincida el modelo solicitado no
controla carga, caché, respaldos del proveedor ni variabilidad; la comparación sigue
siendo descriptiva. Esta implementación se validó sin ejecutar esa campaña pagada.

Pruebas de esta unidad: `teamdb-runtime`, `workflow-engine`, `memory-efficiency`,
`agent-outcomes`, `data-safety`, `teamdb-memory-writes`, restauración
e instalación aislada, además de los contratos de cápsulas. La conexión y la
migración se distribuyen juntas; el cambio de recuperación FTS y el evaluador pueden
revertirse por separado. Las columnas derivadas y los índices pueden permanecer al
volver al motor anterior: no obligan a eliminar memoria ni a reconstruir el historial.

## Bloqueos pertinentes y memoria en conflicto

Los nuevos pedidos incluyen `finding_contract: 1`. Para bloquear, `reject` requiere
hallazgos estructurados con `outcome_id` válido o `risk` (impacto concreto) y `files`
dentro del alcance revisado. `rescope` exige el resultado que necesita los archivos
adicionales. Una preferencia opcional sigue usando `defer`; un rechazo inválido no
consume entregas, borra evidencia ni cambia estado. Workflows antiguos conservan
compatibilidad sin inventar retroactivamente justificaciones. Una referencia válida
no demuestra por sí sola que el razonamiento del modelo sea correcto.

La recuperación consulta por lotes los enlaces `contradicts` y `supersedes` de
TeamDB. Expone referencias incluso si el otro extremo no coincidió con la consulta.
`requires_resolution` señala un conflicto entre registros vigentes o un reemplazo
entrante; no elige automáticamente un ganador. Una decisión retirada no provoca
un conflicto nuevo. Hasta cuatro referencias por registro y 128 enlaces por lote;
si se supera el límite, `relations_truncated` advierte que falta inspección.
Los metadatos de conflicto cuentan dentro del presupuesto de la cápsula: no se
recortan decisiones para ocultar relaciones. Esto detecta relaciones registradas,
no contradicciones semánticas que nadie haya anotado. No bloquea tareas ajenas al
conflicto ni convierte la memoria histórica en autorización.

El cálculo global de huellas para reutilizar pruebas libera la transacción de
escritura. Antes de utilizar su resultado se comprueban la revisión del workflow
y el candidato actual. El cálculo posterior a una prueba ocurre antes de retomar
el bloqueo. No se reemplazan hashes de contenido por una caché insegura; el recorrido
puede seguir siendo costoso, pero no retiene el escritor de TeamDB. Una cápsula de
task con descubrimiento comprueba la vigencia de las fuentes una sola vez.

## Presupuestos explícitos y evaluación de revisión

`start.resource_budget` admite `max_checks` y `max_elapsed_seconds`, enteros positivos
proporcionados por el usuario. Sin presupuesto explícito no se inventa uno. Cuenta
procesos de verificación iniciados, incluidos probes, verificaciones automáticas y
reintentos que terminaron en timeout; reutilizar evidencia no inicia un proceso nuevo.
El tiempo es transcurrido desde el pedido, incluyendo esperas. `supersedes` conserva
el origen y el consumo; cambiar límites exige una `focus_revision` explícita.
Al agotarse se rechazan pruebas nuevas, manteniendo disponibles revisión de evidencia,
cierre válido y cancelación. `status.execution_budget` informa límites, consumo y
motivos de agotamiento. Este control no limita llamadas al modelo ni comandos externos
al motor: no es un tope duro de tokens o gasto del proveedor.

`tests/evals/reviews.py --prompts` genera seis candidatos con defectos introducidos y
código correcto con posibles mejoras opcionales. El revisor responde con id,
candidate_sha256 y blocking_lines; `--predictions archivo.json` mide aciertos,
falsos positivos y defectos omitidos. El evaluador exige todos los casos y la identidad
del candidato, sin pedir al modelo que se califique. Sus pruebas distinguen rechazar
todo de aprobar todo. Evalúa localización de defectos en ejemplos pequeños, no la
calidad semántica completa de las explicaciones. No se ejecutaron modelos para esta
validación, y no se atribuyen resultados de competencia al equipo.

Validación: workflow-engine, teamdb-runtime, memory-efficiency, review-cycle,
review-calibration, agent-outcomes e instalación aislada. Retirada: los módulos
`skalling_budget` y `skalling_memory_relations` se distribuyen con sus importadores;
retirar sus integraciones antes de quitar los módulos. Los campos JSON aditivos y
los enlaces existentes pueden permanecer en TeamDB. No requiere borrar memoria.

## Conversaciones grandes y ediciones declarativas (0.19.0)

El guard de contexto solicita compactación nativa acotada, sin reescribir mensajes;
TeamDB mantiene el estado del workflow. El umbral es aproximado y la llamada en
curso puede conservar el payload previo. La vía declarativa elimina cargas
rutinarias de TDD/Ponytail y tests artificiales, manteniendo verificación por riesgo.
Configuración, medición, validación y límites: [release 0.19.0](releases/0.19.0.md).
