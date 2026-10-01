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

El complemento observa comandos repetidos, salidas filtradas y esperas largas
y añade recordatorios concretos al siguiente contexto. Conserva solamente
hashes de los últimos 32 comandos por sesión, hasta 64 sesiones, sin guardar
salida ni texto de comandos. No hace consultas a disco, red, base de datos ni
modelos en sus hooks; no modifica ni ejecuta comandos y no añade gates.

Esto orienta al modelo: no garantiza que obedezca ni representa una reducción
de latencia ya medida. No reutiliza automáticamente resultados, porque no puede
demostrar que código, dependencias y entorno siguen iguales. Una repetición
observada no se clasifica automáticamente como desperdicio.

El instalador de Skalling registra el directorio
`plugins/skalling-execution-efficiency` en `plugins` en la configuración, con
`plugins/skalling-execution-efficiency.js` y `plugins/lib/execution-efficiency.mjs`
como hermanos. OpenCode 2.0.21 exige un directorio de paquete, no el archivo JS.
El complemento no se instala globalmente por separado. Se distribuye con
Skalling y solo actúa sobre sus ocho agentes; no cambia permisos ni agentes disponibles. Las
sesiones ya cargadas pueden necesitar reiniciar OpenCode para tomarlo.

Validación focal: `node --test tests/execution-efficiency.test.mjs`.
Prueba con OpenCode real y proveedor sintético local:
`python3 tests/runtime/execution-efficiency-smoke.py` (sin modelo de pago).
Retirada: quitar la entrada de configuración y los cuatro archivos del plugin.
