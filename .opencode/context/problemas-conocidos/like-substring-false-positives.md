---
type: Problem
slug: like-substring-false-positives
title: LIKE substring match puede generar falsos positivos en auto-link decisions→concepts
status: active
discovered_at: 2026-08-05
discovered_by: Luz (auditoría v0.7.6)
workaround_md: |
  Por convención, todos los slugs son kebab-case (sin `%`, `_` ni caracteres
  especiales de LIKE). Si alguien crea un slug con esos caracteres, puede
  generar falsos positivos en R5 de teamdb-link.sh. Por ahora aceptamos el
  riesgo porque la convención es estricta.
---

# LIKE substring match — riesgo de falsos positivos

## Síntoma

R5 de `teamdb-link.sh` usa `body_md LIKE '%' || slug || '%'` para detectar menciones de concepts en decisions. Si un slug contiene `%` o `_` (wildcards de SQL LIKE), podría matchear con texto que no es realmente una mención.

## Causa raíz

SQL LIKE trata `%` (cualquier secuencia) y `_` (cualquier carácter) como wildcards. La query actual no los escapa.

## Workaround

Convención del proyecto: todos los slugs son kebab-case (ej: `modulo-app`, `stack-postgres`, `auth-jwt`). No se usan `%`, `_` ni otros caracteres especiales en slugs.

## Fix futuro (no aplicado)

Cambiar la query a `instr(body_md, slug) > 0` (substring search sin wildcards) o escapar con `replace(replace(slug, '%', '\%'), '_', '\_')`.

## Severidad

Baja. No bloqueante. Solo aplica si alguien rompe la convención de slugs.
