# Trabajo coherente desde la petición hasta el cierre

Desde 0.16.0, `start` conserva el id de routing dentro del workflow. `ready`
recibe el plan aprobado y `task_ids`: las tareas exactas que se van a cubrir.
Si `start` nombró `task: "plan/tarea"`, esa tarea se vincula automáticamente.
Un plan con tareas no acepta un `ready` sin selección explícita.

Cada tarea añade un resultado observable con su aceptación. Jhon/Luz deben
vincularlo a evidencia ejecutada, igual que los resultados de la petición.
`complete` resuelve solo las tareas vinculadas, libera sus reservas y actualiza
routing/métricas en la misma transacción que el workflow. El plan se completa
solo cuando todas sus tareas están aprobadas o resueltas. Repetir `complete`
tras perder la respuesta es idempotente. Cambios posteriores abren otra tarea.

Alex puede usar `cancel` o `fail` con evidencia concreta. Terminan el intento,
no certifican éxito ni descartan el trabajo pendiente: sus tareas no resueltas
vuelven a pendientes. `supersedes` conserva el intento anterior y su motivo.
Las reservas vencidas se limpian al operar; el dashboard no las presenta como
propiedad vigente. No se infiere que un agente está ejecutando solo por una fila.

## Recuperar instalaciones existentes

1. Actualizar el bundle con `setup.sh --target <proyecto>`: migra TeamDB,
   sincroniza skills gestionadas y registro, conserva las personalizadas.
2. Ejecutar `setup-team-doctor.sh --project <proyecto> --reconcile`.
3. Con autorización de reparación, añadir `--apply`. Se crea un backup SQLite
   consistente antes de escribir y todas las reparaciones son transaccionales.
4. Revisar `needs_review`. Una tarea histórica sin evidencia no se convierte en
   terminada por existir un commit o una release. Retomar/cancelar workflows usa
   su mismo id; registrar evidencia y resultados reales antes de cerrar.

La reconciliación enlaza routing antiguo solo si intención y fecha identifican
un único workflow. Para registros antiguos sin intención se exige fecha exacta,
ruta y procedencia `skalling_workflow start`; coincidencias ambiguas no se enlazan. Cierra routing/métricas solo desde un estado terminal ya
registrado, aprueba propuestas cuyo plan ya estaba aprobado, vence reservas y
completa planes que ya tienen todas sus tareas terminadas. No adivina tareas
cubiertas por un workflow antiguo. Los registros inciertos permanecen visibles.

## Memoria, publicación y comprobación

Al cerrar una release, revisar si apareció conocimiento durable: decisiones,
restricciones o problemas recurrentes. Registrar lo nuevo; no crear recuerdos
para cumplir una cuota. Regenerar `db/teamdb/team.dump.sql` después de actualizar
la memoria y antes de preparar el commit compartido.

`tests/scripts-parity.test.sh` comprueba scripts y skills core. La auditoría de
skills detecta también versiones gestionadas antiguas con YAML válido. Las
pruebas del motor cubren cierre parcial, evidencia por tarea, cancelación y
reintentos; las pruebas de comandos cubren reconciliación sin falsos positivos.

Rollback: revertir la unidad de ciclo de vida y sus pruebas conserva la base
(le añade campos al JSON del workflow; no borra tablas). Recuperar el backup
solo si se necesita deshacer una reconciliación y tras revisar trabajo posterior.
