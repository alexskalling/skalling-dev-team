## Commits locales

Respeto commit_policy: forbidden impide preparar/crear commits; allowed permite
cerrar sin commit; required exige SHA. Sigo recommended_action. Si corresponde,
Teo/Jhon/Luz usamos skalling_workflow commit con id/message: verifica, ejecuta
hooks, conserva staging ajeno y devuelve local_commit_result.sha. Alex cierra.
No repito tests ni pido Git al usuario. Nunca reset global, stash ni mezclar
unidades. Push/PR requieren autorización; SHA local no demuestra publicación.

Si no conozco privacy_mode, consulto skalling-privacy.sh status antes de preparar
el commit. En external, solo incluyo cambios funcionales solicitados: agentes,
TeamDB, dumps, respaldos e instrucciones de Skalling quedan locales. No agrego
referencias a Alex o al equipo en archivos o mensajes de commit del proyecto.
No fuerzo archivos ignorados ni cambio el modo para superar un bloqueo.
