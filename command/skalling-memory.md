---
description: Busca, relaciona, visualiza y revisa la memoria TeamDB desde un solo comando.
---

# Skalling Memory

Resuelve siempre la instalación así:

```bash
SK_ROOT="${SKALLING_ROOT:-${SKALLING_OPENCODE_DIR:-$HOME/.config/opencode}}"
PROJECT="$(pwd)"
```

Interpreta el argumento solicitado y delega:

- `search <texto> [tipo]`: `bash "$SK_ROOT/scripts/teamdb-search.sh" <texto> [tipo] "$PROJECT"`.
- `related <slug> [tipo]`: `bash "$SK_ROOT/scripts/teamdb-related.sh" <slug> [tipo] "$PROJECT"`.
- `graph [formato]`: `bash "$SK_ROOT/scripts/teamdb-graph.sh" "$PROJECT" [text|mermaid|dot]` (solo lectura).
- `review`: `bash "$SK_ROOT/scripts/mem-review.sh" --target "$PROJECT" --dry-run`.
- `refresh`: primero `bash "$SK_ROOT/scripts/teamdb-link.sh" "$PROJECT" --dry-run`;
  pide confirmación y solo entonces ejecútalo sin `--dry-run`.

Sin argumentos, muestra estas opciones. Nunca borres recuerdos automáticamente:
presenta candidatos y exige una decisión individual del usuario.

Para exportar un concepto por solicitud explícita:
```bash
python3 ~/.config/opencode/scripts/skalling-memory-layout.py --project "$PWD" --export-concept design-system
```

Para retirar la navegación Markdown antigua de forma recuperable, cuando el usuario
solicite limpiar esa estructura:
```bash
python3 ~/.config/opencode/scripts/skalling-memory-layout.py --project "$PWD" --archive-legacy
```
Conserva bytes en legacy_documents y mueve carpetas a .backups/legacy-memory-*.
No modifica código de aplicación ni planes en .opencode/changes.
