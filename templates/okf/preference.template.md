---
type: Preference
title: [Título de la preferencia]
description: [Una línea]
tags: [estilo, convención]
timestamp: YYYY-MM-DDTHH:MM:SSZ
agent: [quién documentó]
confidence: 1.0
---

# [Nombre de la preferencia]

## Qué

[Convención o preferencia específica del equipo en este proyecto.]

## Por qué

[Razón. Contexto. Si reemplaza una preferencia anterior, link acá.]

## Ejemplos

### ✓ Sí
```typescript
const nombreUsuario = obtenerUsuario();
```

### ✗ No
```typescript
const userName = getUser();
```

## Excepciones

[Si hay casos donde esta preferencia NO aplica, listarlos.]

## Aplicación

- Aplicar en: [código nuevo / PRs / code review / docs]
- Quién enforce: [Teo / Jhon / Luz / todos]
