# Comandos de Skalling

La interfaz pública está organizada por intención:

- Empezar: `/skalling-init`, `/skalling-help`.
- Completar un objetivo hasta un commit local, sin push: `/skalling-goal`.
- Entender: `/skalling-status`, `/skalling-codegraph`, `/skalling-dashboard`, `/skalling-coverage`.
- Memoria: `/skalling-memory`, `/skalling-resume`, `/skalling-metrics`.
- Mantener: `/skalling-refresh`, `/skalling-doctor`, `/skalling-update`, `/skalling-models`.
- Recuperar: `/skalling-recover`, `/skalling-merge`.

Cada comando es un contrato corto. La lógica ejecutable vive en scripts probados;
así no se duplica SQL, detección de plataforma ni rutas dentro de los prompts.
