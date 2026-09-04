# Comandos de Skalling

La interfaz pública está organizada por intención:

- Empezar: `/skalling-init`, `/skalling-help`.
- Entender: `/skalling-status`, `/skalling-resume`, `/skalling-codegraph`, `/skalling-dashboard`.
- Memoria: `/skalling-memory`, `/skalling-metrics`.
- Mantener: `/skalling-refresh`, `/skalling-doctor`, `/skalling-update`.
- Recuperar: `/skalling-recover`, `/skalling-merge`.

Cada comando es un contrato corto. La lógica ejecutable vive en scripts probados;
así no se duplica SQL, detección de plataforma ni rutas dentro de los prompts.
