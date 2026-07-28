# Skalling Init — Setup del proyecto

Al ejecutarse en un proyecto, este comando:
1. Detecta el estado (nuevo / virgen / ya inicializado).
2. Detecta stack (cualquier lenguaje: JS, TS, Python, Rust, Go, Java, Ruby, PHP, Elixir, Swift, Dart, .NET, Deno, Bun).
3. Genera bundle OKF con memoria del proyecto.
4. Crea `project.yaml` con metadata auto-detectada.
5. Para frontend: aplica REGLA #13 (design-system.md obligatorio en bundle OKF).
6. Sugiere skills stack-specific.

## Uso

```
/skalling-init
```

No toma argumentos. Lee el directorio actual.

## Para más detalle

Ver el protocolo completo en este archivo o en `.opencode/command/skalling-init.md` después de instalar.
