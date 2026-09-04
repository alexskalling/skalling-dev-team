---
name: brainstorming
description: "You MUST use this before any creative work - creating features, building components, adding functionality, or modifying behavior. Explores user intent, requirements and design before implementation."
license: MIT
metadata:
  author: skalling-team
  version: "1.0"
---

# Brainstorming Ideas Into Designs

## Overview

Help turn ideas into fully formed designs and specs through natural collaborative dialogue.

Start by understanding the current project context, then ask questions one at a time to refine the idea. Once you understand what you're building, present the design in small sections (200-300 words), checking after each section whether it looks right so far.

## The Process

**Understanding the idea:**
- Check out the current project state first (files, docs, recent commits)
- Ask questions one at a time to refine the idea
- Prefer multiple choice questions when possible, but open-ended is fine too
- Only one question per message - if a topic needs more exploration, break it into multiple questions
- Focus on understanding: purpose, constraints, success criteria

**Exploring approaches:**
- Propose 2-3 different approaches with trade-offs
- Present options conversationally with your recommendation and reasoning
- Lead with your recommended option and explain why

**Presenting the design:**
- Once you believe you understand what you're building, present the design
- Break it into sections of 200-300 words
- Ask after each section whether it looks right so far
- Cover: architecture, components, data flow, error handling, testing
- Be ready to go back and clarify if something doesn't make sense

## After the Design

**Documentation (Skalling protocol — DB como source of truth, NO se escriben .md):**
- Pol NO escribe el design validado como archivo. Devuelve el texto del proposal a Alex vía relay.
- Alex invoca a Sol, quien INSERT en la tabla `proposals` de team.db (vía `teamdb-plan.sh`) y SOLO si el usuario lo pide, exporta un `.md` derivado vía `teamdb-export-md.sh`.
- El header del `.md` debe decir `GENERATED from teamdb`. El export es derivado, no fuente.

**REGLA DURA: NUNCA escribas archivos .md en .opencode/changes/ o .opencode/context/ como fuente de verdad.**
**El pre-commit hook lo BLOQUEA con exit 1.** Si necesitas crear un plan → `teamdb-plan.sh`. Si necesitas guardar contexto → INSERT en la DB correspondiente.

**Existente `.md` ≠ fuente.** Si hay `.md` en `.opencode/context/` con contenido que no está en la DB, migrar: leer el contenido, INSERTAR en la tabla correspondiente, el `.md` pasa a ser export. Usar `migrate-legacy-md-to-db.sh` para migración masiva.

**Implementation (if continuing):**
- Ask: "Ready to set up for implementation?"
- Alex invoca a Sol (skill `writing-plans`) si todavía no hay un plan estructurado.

## Key Principles

- **One question at a time** - Don't overwhelm with multiple questions
- **Multiple choice preferred** - Easier to answer than open-ended when possible
- **YAGNI ruthlessly** - Remove unnecessary features from all designs
- **Explore alternatives** - Always propose 2-3 approaches before settling
- **Incremental validation** - Present design in sections, validate each
- **Be flexible** - Go back and clarify when something doesn't make sense
