---
name: skalling-impeccable-bridge
description: Revisar cambios visuales respetando el sistema de diseño existente y el alcance solicitado.
---

# Trabajo visual

Activar cuando Teo modifica UI o Luz revisa cambios visuales.
Primero leer la evidencia del proyecto, después elegir herramientas opcionales.

1. Recuperar la cápsula usando el pedido completo y --visual.
2. Leer completa la fila concepts/design-system mediante teamdb-read.sh.
3. Abrir los componentes implicados, sus imports, estilos y referencias de diseño.
4. Identificar la fuente canónica reutilizable. Si dos identidades válidas compiten,
   devolver a Alex la decisión para el usuario.
5. Conservar tipografía, colores y estructura ajenos al alcance aprobado.
6. Verificar antes/después en las superficies y tamaños afectados. Si no hay acceso
   a navegador, reportar esa limitación; los tests de código no acreditan fidelidad visual.

No instalar ni ejecutar herramientas por una suposición sobre el framework.
Si Impeccable ya está disponible, consultar su ayuda y usar únicamente capacidades
reales pertinentes al pedido. Su ausencia no bloquea la revisión con herramientas existentes.

La memoria se conserva en TeamDB mediante Pau y teamdb-memory.sh.
No ejecutar SQL interpolado ni helpers de consulta como si fueran escritores.
No crear PRODUCT.md, DESIGN.md o carpetas internas como requisito de trabajo.
Una exportación humana, si se solicita, se genera desde la DB en .opencode/exports/.

La preferencia genérica por una biblioteca o estética nunca sustituye las convenciones
del proyecto ni autoriza rediseñar una pantalla.
