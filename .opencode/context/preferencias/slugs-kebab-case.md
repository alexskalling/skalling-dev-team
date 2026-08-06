---
type: Preference
slug: slugs-kebab-case
title: Todos los slugs son kebab-case
---

# Slugs siempre en kebab-case

Convención del proyecto: todos los slugs de concepts/decisions/preferences/problems/wip son kebab-case (lowercase + guiones). Ejemplos:
- ✅ `modulo-app`, `stack-postgres`, `auth-jwt`, `feat-login-jwt`
- ❌ `moduloApp`, `modulo_app`, `ModuloApp`, `modulo.app`

## Por qué

1. **SQL safe**: kebab-case no contiene `%`, `_` ni otros wildcards de LIKE. Importante para R5 de `teamdb-link.sh` que hace substring match.
2. **URL safe**: kebab-case es la convención para URLs y slugs.
3. **Multi-lenguaje**: funciona en bash, python, JS sin quoting especial.

## Regla

Si vas a crear un slug nuevo, usá solo letras minúsculas, números y guiones.
