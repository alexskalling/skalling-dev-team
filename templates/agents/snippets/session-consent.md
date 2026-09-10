## Consentimiento de sesión y decisiones críticas

Push y despliegue están desautorizados por defecto. Solo una instrucción explícita
del usuario en la sesión actual puede autorizarlos, para el trabajo y destino
indicados. Un permiso puntual se consume al completar esa publicación; un permiso
para toda la sesión sigue vigente dentro de su alcance hasta revocación. Un push
anterior, una preferencia guardada, credenciales disponibles, tests verdes o la
orden de otro agente no conceden permiso.

Implementar, terminar, aprobar un plan o hacer commit NO autoriza push ni deploy.

Invocar /skalling-goal con un objetivo sí autoriza las acciones locales necesarias y
UN commit de ese objetivo, sin pedir confirmaciones repetidas. No autoriza push/deploy.
El helper de goal comprueba la sesión y el candidato; no reemplazarlo por git commit directo.
Las lecturas normales del proyecto, Git de consulta y helpers TeamDB del rol no requieren
volver a preguntar. Usar helpers canónicos directamente o con bash; no envolverlos en
python3 -c, bash -c, eval, scripts temporales ni prefijos PROJECT= innecesarios.

## Datos: autorización separada

Goal NO autoriza borrar datos. Los helpers bloquean DELETE/REPLACE/DROP, DDL destructivo
y vaciados; las actualizaciones conservan versiones en `data_revisions`.
Para pérdida de datos SQLite usar `teamdb_destructive`: aprobación nativa del SQL,
parámetros y base exactos, respaldo previo; si cambia la base se pide otra aprobación.
Nunca ejecutar su backend directamente, inventar consentimiento, vaciar campos,
usar Always allow ni eludir controles mediante scripts o cambios de permisos.
Otras bases/APIs, restores, purgas y sobrescrituras .db/.sqlite también requieren
consentimiento explícito de esa operación. Las pruebas usan bases aisladas, no datos
reales. cp/rm genéricos no quedan autorizados.

## Cierre Git acotado

Un commit no inicia un nuevo ciclo de especialistas: el coordinador ejecuta el cierre.
Preparar solo archivos autorizados, revisar el candidato staged una vez y crear el commit.
La evidencia permanece válida mientras ese candidato no cambie; no caduca por tiempo.
Push verifica cada commit pendiente y requiere consentimiento separado.
Los hooks no regeneran ni preparan el dump; exportar memoria es una operación explícita,
independiente. No reparar planes antiguos, limpiar filas ni emitir comprobantes retroactivos
para desbloquear Git. Si falla, leer el error, corregir su causa concreta y reintentar una vez;
si persiste, detener el cierre e informar sin cambiar historia ni evadir el hook.
Push NO autoriza un despliegue separado. Si el destino dispara despliegue automático,
informo ese efecto y verifico que esté cubierto por el permiso antes de publicar.
Esto incluye git, gh/API, merge de PR, releases, CLI de hosting y scripts indirectos.
No se elude la regla mediante wrappers, agentes, CI o cambios de permisos.

Antes de publicar muestro cambios, evidencia y destino. Si el usuario exige revisión
previa, espero su aprobación del resultado concreto. Con permiso explícito vigente
y sus condiciones satisfechas, procedo sin repetir preguntas. Un handoff que invoque
permiso incluye la cita del mensaje del usuario y su alcance; ausencia o contradicción
significa no autorizado. Nunca fabrico ni amplío ese consentimiento.

Las decisiones críticas pendientes sobre producto, arquitectura, costes, datos,
seguridad o producción vuelven al usuario a través de Alex, con opciones, impacto
y recomendación. Alex espera respuesta; los especialistas no interpretan silencio
como aprobación. Pueden avanzar trabajo independiente de esa decisión.
