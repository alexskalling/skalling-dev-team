---
description: Completa un objetivo con verificación y commit local, sin push ni despliegue.
agent: Alex
---

# Skalling Goal

Pedido del usuario: $ARGUMENTS

El plugin registra el objetivo y el consentimiento para UN commit local en TeamDB.
Esto NO concede permiso para eliminar datos: usar `teamdb_destructive` con aprobación
humana cuando una operación SQLite implique pérdida de datos, también durante Goal.
Si no aparece el estado verificado del plugin, no simules el modo autónomo: informa
que falta cargar el plugin y que hay que reiniciar OpenCode.

- Sin argumentos o `status`: mostrar estado, sin continuar.
- `pause`: pausar. `resume`: continuar el mismo objetivo. `cancel`: cancelar sin borrar trabajo.
- Otro texto: es el objetivo. Su invocación autoriza implementar, verificar y hacer su commit;
  NO autoriza push, deploy, publicación, cambios fuera del proyecto ni decisiones críticas pendientes.

## Ejecución

1. Recuperar contexto, clasificar riesgo y delegar proporcionalmente con el flujo normal de Alex.
   No preguntar por lecturas, pruebas, delegaciones y memoria necesarias para el pedido.
2. Respetar los archivos previos protegidos que devuelve el estado. No tocar esos cambios,
   salvo una nueva autorización explícita; el commit automático no los incluirá.
3. Continuar hasta satisfacer la aceptación. Investigar fallos; no ampliar el alcance para mejorar de más.
4. Jhon verifica independientemente; Luz participa cuando el riesgo lo requiere; Pau guarda memoria durable.
5. Registrar un checkpoint con aceptación, comandos, resultados reales y limitaciones mediante:

```bash
bash ~/.config/opencode/scripts/skalling-goal.sh checkpoint "<evidencia real y aceptación satisfecha>"
bash ~/.config/opencode/scripts/skalling-goal.sh commit "<mensaje descriptivo>" "<archivo1>" "<archivo2>"
```

El primer intento prepara SOLO esa lista. Si falta revisión del candidato, ejecutar
`bash ~/.config/opencode/scripts/skalling-review.sh` y volver a llamar commit con la misma lista.
No ejecutar git add/commit directamente, ni usar --no-verify, amend, reset, push o wrappers equivalentes.
El helper comprueba el candidato, ejecuta los hooks y marca completed únicamente tras un commit real.

Si falta una decisión crítica o hay bloqueo real:

```bash
bash ~/.config/opencode/scripts/skalling-goal.sh block "<causa concreta>"
```

Preguntar solo por esa decisión. La continuación automática se limita a 20 turnos adicionales
y se detiene tras 3 sin cambios de archivos o checkpoints. No repetir checkpoints para eludir ese límite.
No prometer autonomía ilimitada ni omitir controles. Tras reiniciar OpenCode, usar `resume` en
la misma sesión para retomar el objetivo pendiente. Consultar `status` no reactiva un ejecutor detenido.
Al terminar: resumen, pruebas realizadas, hash del commit y confirmación de que no hubo push.
