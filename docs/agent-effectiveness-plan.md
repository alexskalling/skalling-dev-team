# Plan para que el equipo termine mejor y más rápido

## Objetivo

El producto evaluado es el arnés: debe ayudar al modelo a entender el pedido,
recuperar contexto pertinente, decidir un alcance, ejecutar con continuidad,
recibir feedback útil y entregar el resultado al usuario. Su responsabilidad
incluye hacer visibles las capacidades faltantes del runtime y ofrecer una
recuperación clara; atribuir el fallo al modelo no resuelve esa responsabilidad.

Reducir rondas y tiempo sin bajar calidad. Una tarea cuenta como terminada si
el cambio cumple un resultado observable, la evidencia cubre ese resultado y
el agente deja de editar. Los agentes no reciben crédito por cantidad de
archivos, tests ejecutados o texto producido.

## Veredicto del producto (snapshot del 30-09-2026)

**No cumple todavía de forma consistente la promesa de completar objetivos de
software con rapidez y efectividad.** Sí cumple parte de la promesa de control:
workflow auditable, revisión de riesgo y bloqueo de operaciones peligrosas.
Eso no equivale a entregar funcionalidades aceptadas con pocas vueltas.

La TeamDB local tenía 10 workflows: 1 `completed`, 1 `superseded` y 8 aún
abiertos (7 en `implementation_ready`, 1 `verified`). El workflow exitoso de
riesgo alto duró 108,9 minutos; otro de riesgo alto seguía `verified` sin
`complete`. Es una muestra pequeña de desarrollo, no un benchmark estadístico,
pero expone un fallo concreto: varios pedidos llegan a la puerta de
implementación y no quedan registrados como terminados.

El README contiene sesiones puntuales más rápidas, incluyendo una tarea trivial
de 30 segundos, pero también reconoce que son fixtures/proyectos chicos y que
OpenCode 2.x no tiene `/skalling-goal`: en esa versión el flujo necesita que
una persona lo conduzca y no continúa objetivos por sí mismo. La cobertura de
tests valida contratos y seguridad; no demuestra aceptación del usuario ni
calidad de producto. La evaluación real con proveedor sigue pendiente.

Durante esta revisión también se encontró una decisión de despacho divergente:
el motor mandaba por defecto un cambio local `medium` a Sol, aunque la regla
focused decía Teo → Jhon. Ahora ambos usan la ruta directa; los cambios de
módulo, sensibles y con plan conservan staged. Esto elimina esa contradicción,
pero no basta para declarar que el producto ya cumple su objetivo.

También se encontró una fuente directa de lentitud para proyectos instalados:
si no declaraban `testing.fast`, el motor ejecutaba automáticamente todo
`testing.unit` incluso para un cambio local trivial. El motor ahora automatiza
solo `testing.fast`; sin ese comando Jhon escoge una prueba focal y decide si el
impacto amerita la suite completa. `testing.unit` sigue disponible para
verificación explícita y queda congelado al iniciar el workflow.

## Prioridad 0: evitar ciclos sin salida — aplicado

- Cada workflow permite como máximo tres candidatos: el cambio inicial y dos
  correcciones.
- Jhon, Luz y la verificación automática guardan la última causa de rechazo.
- El siguiente handoff expone `recommended_action`, `last_rejection` y las
  entregas restantes. Teo debe corregir esa causa concreta.
- El tercer candidato rechazado pone el workflow en `blocked`. Alex debe parar,
  aclarar alcance/aceptación y abrir un workflow que superseda al anterior.

Beneficio: evita una hora de cambios y reversiones sin límite; cada nueva vuelta
tiene motivo, dueño y presupuesto visible.

## Prioridad 1: un solo flujo corto para trabajo local — aplicado y alineado

- `focused` conserva un solo dueño de implementación. Low usa verificación
  automática focal; medium agrega Jhon; high conserva Jhon y Luz.
- Para un microcambio, Teo inspecciona hasta tres archivos y prueba dos
  hipótesis antes de devolver evidencia a Alex. El tope de entregas lo aplica
  el motor; el límite de lectura es una instrucción del perfil.
- Pol y Sol entran si hay una decisión de producto o una descomposición que
  realmente requiere plan. Pau entra si apareció conocimiento durable.
- Se corrigieron descripciones contradictorias del workflow y del guard. El
  estado del motor y `recommended_action` deciden quién sigue.

Beneficio: menos handoffs, menos repetición de lectura y menos llamadas para
un cambio local. El flujo staged permanece para decisiones transversales y
planes existentes.

## Prioridad 2: medir resultado, costo y alcance — mejorado; evaluación real pendiente

El runner de evaluaciones ahora registra por caso: resultado del oracle,
estado final, número de entregas, rechazos, archivos cambiados, duración,
handoffs y tokens cuando TeamDB los tenga. La cantidad de correcciones humanas
queda como desconocida cuando no hay una conversación de evaluación que las
mida; no se inventa un cero.

La evaluación exige comportamiento correcto según el oracle externo, proceso
exitoso, alcance respetado y workflow `completed`. Conserva `behavior_passed`
por separado: un parche correcto abandonado en `verified` es un fallo de entrega
del arnés. Antes, ese caso podía aparecer como éxito.

Siguiente paso operativo: ejecutar la batería con un proveedor disponible y
guardar un baseline antes de afirmar que el agente mejoró. La ejecución previa
no pudo completarse por el límite de uso del proveedor, así que aquí no se
declara una mejora medida del rendimiento del equipo usando el arnés.

## Prioridad 3: comprobar la calidad que pidió la persona

Para cada tarea, Alex debe convertir el pedido en una frase de aceptación que
se pueda falsar. Ejemplos:

- UI: elemento objetivo, estado visual esperado, viewport afectado y qué debe
  permanecer igual. Evidencia: estilo/medida DOM o captura si el proyecto tiene
  navegador automatizable.
- Lógica: entrada normal, caso límite, salida esperada e invariante de API.
- Refactor: comportamiento preservado y superficie de archivos permitida.

Una prueba verde solo cuenta si comprueba esa aceptación. No se debe correr la
suite completa por defecto cuando el proyecto tiene un comando focal que cubre
el cambio.

La respuesta compacta de `skalling_workflow` conserva el oracle independiente y
el criterio y método de cada check. Así, Alex y Luz pueden juzgar qué requisito
se comprobó sin recuperar el log entero. Antes, el resumen solo mostraba el
comando y su exit code, perdiendo el vínculo con el resultado solicitado.

Una comprobación automática ya no se etiqueta como si cubriera todo `acceptance`:
registra regresión configurada. Cuando Alex detecta cobertura insuficiente,
Jhon puede abrir `oracle` sobre ese `verified`, conservar los checks válidos y
probar el comportamiento faltante. El motor impide cerrar durante esa revisión
y no vuelve al cierre automático tras una corrección. Detectar la pertinencia
sigue siendo un juicio del agente; el motor habilita y protege la recuperación.

## Prioridad 4: medir aceptación humana — instrumentado en 0.15.0

El runner no puede inferir si la persona quedó satisfecha. La acción `feedback` de Alex registra explícitamente si una respuesta posterior fue una
corrección, un cambio de alcance o una nueva tarea, junto con el motivo. No
inferirlo solo por el tono ni convertir una pregunta en una “iteración fallida”.
Con esa señal explícita se puede optimizar por aceptación sin corrección y no solo
por duración o tokens.

## Prioridad 5: mantener una sola fuente de verdad

Los contratos que gobiernan el flujo deben derivarse del motor o probarse
contra él: plugin, perfiles, guard, handoff y documentación. Cambiar una regla
en un prompt sin actualizar el estado ejecutable vuelve a crear rutas
contradictorias. Cada ajuste futuro debe incluir el texto canónico, sus
consumidores y una prueba de contrato.

## Límite actual

El arnés puede imponer un presupuesto de entregas, pero el plugin no recibe un
contador autoritativo de llamadas del modelo. El límite de archivos e hipótesis
es una instrucción y puede ser incumplido. Un corte duro por herramientas o
minutos requiere soporte del runtime o un wrapper de ejecución; no se debe
presentar el límite actual como enforcement completo.

## Criterios de éxito

- En los fixtures, el oracle externo pasa y solo cambian los archivos
  declarados.
- Los cambios focused terminan con máximo tres entregas.
- Cada rechazo posterior llega a Teo con una causa concreta y una acción
  siguiente estructurada.
- Se comparan duración, handoffs, tokens y entregas contra un baseline real.
- Se mide por separado el número de correcciones humanas; no se usa una cifra
  supuesta como proxy de satisfacción.

## Entrega 0.15.0: objetivo, contexto, repetición y medición

Aplicado en el motor: `start` exige `intent` y conserva `outcomes` con identificadores
estables; si solo hay un resultado, usa `acceptance`. Cada aprobación debe aportar
`coverage` para todos los resultados con índice de check y observación. No acepta
índices inexistentes, evidencia fallida, sustituida o de otro candidato. La revisión
independiente relaciona sus propios checks. `complete` reutiliza esa relación; el
carril automático exige que Alex la aporte. Teo puede aportarla al preparar un
commit de riesgo bajo. Una nueva entrega, revisión o ampliación invalida la relación.
La correspondencia semántica sigue siendo juicio del revisor, no una promesa de
que el código pueda detectar cualquier observación falsa.

Contexto: el mapa incluye todos los directorios de producto no ocultos ni generados.
La huella de README, manifiestos, versión, configuración y módulos distingue
`current`, `stale` y `unknown`; `current` describe esas fuentes, no certifica cada
frase de la memoria. Se preservan ediciones humanas y se señalan divergencias.
Las cápsulas de tareas conservan `purpose` y solo problemas abiertos. El
redescubrimiento usa términos únicos y LIMIT en SQL.

Repetición: `for-request --seen=<read_key>` omite solo cuerpos ya presentes en el
contexto del llamador e idénticos por hash. No se transmite ese supuesto de lectura
a otro agente. `auto_verify` es visible para que Teo no duplique ese comando.
Un check marcado reusable puede reutilizarse por el mismo revisor durante diez
minutos con igual comando, método, criterio, candidato y huella del entorno; el
primer fallo o un cambio invalida el ahorro. La herramienta comparte una descripción
breve entre runtimes en lugar de repetir el manual de roles.

Medición: `feedback` identifica cada mensaje humano y registra corrección, aceptación,
cambio de alcance o nueva tarea sin duplicarlo. No modifica el estado de entrega
ni atribuye satisfacción al silencio. El runner de `tests/evals/run.py` admite
`--baseline`, compara casos idénticos y conserva desconocidos como null. Incluye
checks externos de comportamiento, cierre, cambios ya commiteados, duración,
consumo disponible y correcciones registradas. La comparación se etiqueta no
controlada: aún requiere ejecuciones reales comparables antes de afirmar un ahorro.

Validación: pruebas de contrato y fixtures reales de Git/SQLite cubren estos límites;
la evaluación con proveedor se registra por separado. Rollback de la entrega:
revertir el commit 0.15.0 restaura código, prompts y configuración previos; los campos
adicionales en JSON no requieren borrar memoria ni historial de workflows.
