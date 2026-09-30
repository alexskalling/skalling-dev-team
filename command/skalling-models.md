---
description: Asigna un modelo de OpenCode a cada agente de Skalling, individualmente.
---

# Skalling Models

Cada uno de los 8 agentes (Alex, Jes, Jhon, Luz, Pau, Pol, Sol, Teo) puede usar un
modelo distinto — por ejemplo, los agentes que piensan más (Pol, Sol) con un modelo
más potente, y los agentes rápidos/administrativos (Teo, Jhon) con uno más liviano.
Un agente sin asignación explícita usa el modelo default de la sesión de OpenCode,
como siempre.

Este comando NO inventa nombres de modelo. Corré `opencode models` para ver los IDs
disponibles en tu instalación antes de asignar.

```bash
SK_ROOT="${SKALLING_ROOT:-${SKALLING_OPENCODE_DIR:-$HOME/.config/opencode}}"
bash "$SK_ROOT/scripts/skalling-models.sh" "$@"
```

Uso:
- `/skalling-models` o `/skalling-models show` — modelo actual de cada agente.
- `/skalling-models set Alex anthropic/claude-opus-5` — asigna un modelo a un agente.
- `/skalling-models reset Alex` — vuelve ese agente al default de la sesión.
- `/skalling-models reset` — vuelve los 8 agentes al default de la sesión.

La asignación queda en `model-overrides.json`, en tu instalación global (no en el
repo de Skalling) — sobrevive a un `/skalling-update` o reinstalación, porque
install-global.sh la vuelve a aplicar después de regenerar los agentes.

## Recuperación automática (0.15.1)

Requiere **OpenCode 2.0.18** con los hooks nativos `session.retry` y
`session.switchModel`. OpenCode v1 no soporta este mecanismo. Primero consulta
`opencode models` y sustituye los IDs de ejemplo por modelos que tengas disponibles:

```text
/skalling-models fallback set Teo proveedor/modelo-respaldo proveedor/segundo-respaldo
/skalling-models fallback timeout Teo 180 60
/skalling-models fallback show
/skalling-models fallback reset Teo
```

Reinicia OpenCode después de cambiar la política. `model-fallbacks.json` conserva
la cadena al reinstalar. Sin una cadena configurada no se activa el plugin ni se
escoge un proveedor automáticamente. `reset Teo` cambia el modelo principal;
`fallback reset Teo` desactiva exclusivamente su respaldo.

Si el proveedor falla, no responde dentro del plazo o devuelve salida inválida,
el runtime selecciona el siguiente modelo disponible en **la misma ejecución**.
Conserva la sesión, el agente, el objetivo y el historial de herramientas. No crea
una tarea nueva ni vuelve a enviar la petición inicial. El respaldo queda como
modelo de esa sesión; la asignación principal del agente no se modifica.

La cadena admite hasta tres respaldos distintos, una visita por modelo en cada
recuperación; también aplica el límite nativo de intentos de OpenCode. Si ninguno
sirve, el fallo queda visible, sin reintentos interminables. Los registros
`[skalling-fallback]` muestran modelo anterior, siguiente y clase de error; nunca
copian el prompt, las credenciales ni la respuesta del proveedor.

Los plazos predeterminados son 180 segundos totales y 60 de silencio entre datos.
OpenCode configura estos límites **por proveedor**: al activar una política se
aplica el menor plazo configurado a los proveedores de esta instancia, también
en llamadas de otros agentes. Un límite existente más estricto se conserva.
Una generación larga puede requerir ampliar los plazos (máximo 600 segundos).

No cambia de modelo por una cancelación del usuario, permiso rechazado, prueba
fallida, filtro de contenido ni petición malformada (excepto modelo no encontrado,
HTTP 404). Tampoco determina automáticamente que una respuesta coherente sea
mediocre: eso corresponde a la revisión y a la evidencia del objetivo. La detección de vacío observa SSE de Chat Completions, Responses, Anthropic y
Gemini, además de Responses por WebSocket; protocolos desconocidos conservan la
validación del runtime. Títulos,
compactaciones y generaciones auxiliares conservan sus reintentos nativos.

Ensayo reproducible sin proveedores externos, con OpenCode instalado:

```bash
python3 tests/runtime/model-fallback-smoke.py
SKALLING_SMOKE_FAILURE=timeout python3 tests/runtime/model-fallback-smoke.py
SKALLING_SMOKE_FAILURE=empty python3 tests/runtime/model-fallback-smoke.py
SKALLING_SMOKE_FAILURE=tools python3 tests/runtime/model-fallback-smoke.py
```
