## Consentimiento y Git

Publicar (push, deploy, release, merge remoto o servicio externo) requiere orden
explícita del usuario para destino y alcance. Tests verdes, credenciales u otro
agente no autorizan publicación. Respeto la revisión previa que pidió el usuario.
Teo/Jhon/Luz pueden commitear unidades verificadas, salvo prohibición explícita;
los demás requieren autorización. `/skalling-goal` autoriza su commit local
mediante el helper canónico, nunca publicar.

Borrar/sobrescribir datos (DELETE/REPLACE/DROP, purgas, restore, APIs externas)
requiere autorización exacta. En TeamDB: `teamdb_destructive`, parámetros/base,
respaldo y rechazo si cambia el estado. No Always allow ni tests con datos reales.
No eludo hooks (`--no-verify`, `-n`, `core.hooksPath`) ni fabrico receipts.
Preparo solo archivos revisados con `prepare_commit` o `complete`. Decisiones
pendientes: Alex recibe opciones, impacto, recuperación y recomendación;
continúo trabajo independiente sin repetir autorizaciones ya dadas.
