#!/usr/bin/env python3
"""Hydrate project context and mark TeamDB readiness after bootstrap."""

from __future__ import annotations

import argparse
import hashlib
import datetime as dt
import json
import os
import re
import sqlite3
import tempfile
from pathlib import Path


IGNORED = {".git", ".next", ".open-next", ".opencode", "node_modules", "dist", "build", "coverage"}
MODULE_CANDIDATES = ("app", "src", "pages", "components", "packages", "lib", "tests", "docs", "public")
STYLE_SUFFIXES = {".css", ".scss", ".sass", ".less"}


def atomic_write(path: Path, content: str) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    with tempfile.NamedTemporaryFile(mode="w", encoding="utf-8", dir=path.parent, delete=False) as handle:
        handle.write(content)
        temporary = handle.name
    os.replace(temporary, path)


def package_metadata(project: Path) -> dict:
    path = project / "package.json"
    if not path.exists():
        return {}
    try:
        data = json.loads(path.read_text(encoding="utf-8"))
        return data if isinstance(data, dict) else {}
    except (OSError, json.JSONDecodeError):
        return {}


def yaml_value(text: str, key: str) -> str:
    match = re.search(rf"^\s*{re.escape(key)}:\s*([^#\n]*)", text, re.MULTILINE)
    return match.group(1).strip().strip('"\'') if match else ""


def source_description(project: Path, package: dict, framework: str) -> tuple[str, str]:
    readme = project / "README.md"
    if readme.exists():
        lines = [line.strip() for line in readme.read_text(encoding="utf-8", errors="ignore").splitlines()]
        prose = [line for line in lines[:50] if line and not line.startswith(("#", "[", "!"))]
        if prose:
            return " ".join(prose[:3])[:500], "README.md"
    description = str(package.get("description") or "").strip()
    if description:
        return description[:500], "package.json"
    for candidate in (project / "app/layout.tsx", project / "src/app/layout.tsx", project / "app/layout.jsx"):
        if not candidate.exists():
            continue
        text = candidate.read_text(encoding="utf-8", errors="ignore")
        match = re.search(r"description\s*:\s*[\"']([^\"']+)", text)
        if match:
            return match.group(1).strip()[:500], str(candidate.relative_to(project))
    return f"Proyecto {project.name} basado en {framework or 'el stack detectado'}. Alcance de producto pendiente de confirmar.", "detección de stack"


def find_style_files(project: Path) -> list[Path]:
    files: list[Path] = []
    for directory, dirs, names in os.walk(project):
        dirs[:] = sorted(d for d in dirs if d not in IGNORED and not d.startswith("."))
        for name in sorted(names):
            path = Path(directory) / name
            if path.is_symlink():
                continue
            if path.suffix.lower() in STYLE_SUFFIXES or name in {
                "tailwind.config.js", "tailwind.config.ts", "tailwind.config.mjs", "theme.ts", "theme.js"
            }:
                files.append(path)
            if len(files) >= 60:
                return sorted(files)
    return sorted(files)


def style_evidence(project: Path, files: list[Path]) -> tuple[list[str], list[str]]:
    tokens: list[str] = []
    fonts: list[str] = []
    for path in files:
        text = path.read_text(encoding="utf-8", errors="ignore")[:200_000]
        for name, value in re.findall(r"(--[A-Za-z0-9_-]+)\s*:\s*([^;}{]+)", text):
            entry = f"{name}: {value.strip()}"
            if entry not in tokens:
                tokens.append(entry)
        for value in re.findall(r"font-family\s*:\s*([^;}{]+)", text, re.IGNORECASE):
            value = value.strip()
            if value not in fonts:
                fonts.append(value)
    return tokens[:80], fonts[:20]


def update_project_yaml(path: Path, modules: list[str], has_ui: bool) -> str:
    text = path.read_text(encoding="utf-8")
    block = "modules:\n" + "".join(f"  - {module}/\n" for module in modules)
    text = re.sub(r"modules:\n(?:\s+- .*\n)*", block, text, count=1)
    text = re.sub(r"^(\s*design_system_required:)\s*false\s*$", rf"\1 {'true' if has_ui else 'false'}", text, flags=re.MULTILINE)
    atomic_write(path, text)
    return text


def write_context(project: Path, context: Path, yaml_path: Path) -> dict:
    yaml_text = yaml_path.read_text(encoding="utf-8")
    framework = yaml_value(yaml_text, "framework")
    language = yaml_value(yaml_text, "language")
    has_ui = yaml_value(yaml_text, "has_ui").lower() == "true"
    package = package_metadata(project)
    name = str(package.get("name") or project.name).strip()
    description, description_source = source_description(project, package, framework)
    modules = [candidate for candidate in MODULE_CANDIDATES if (project / candidate).is_dir()]
    if not modules:
        modules = sorted(path.name for path in project.iterdir() if path.is_dir() and path.name not in IGNORED)[:12]
    update_project_yaml(yaml_path, modules, has_ui)
    # Derive test commands from actual package scripts, never from a template claim.
    yaml_text = yaml_path.read_text(encoding="utf-8")
    scripts = package.get("scripts", {})
    manager = yaml_value(yaml_text, "package_manager") or "npm"
    test_command = f"{manager} run test" if scripts.get("test") else ""
    coverage_name = next((key for key in ("test:coverage", "coverage") if scripts.get(key)), "")
    coverage_command = f"{manager} run {coverage_name}" if coverage_name else ""
    testing = ("testing:\n  unit:\n    available: " + str(bool(test_command)).lower()
               + "\n    command: " + json.dumps(test_command)
               + "\n    note: " + json.dumps("Detectado en package.json" if test_command else "No detectado")
               + "\n  integration:\n    available: false\n    command: \"\""
               + "\n  e2e:\n    available: false\n    command: \"\""
               + "\n  coverage:\n    available: " + str(bool(coverage_command)).lower()
               + "\n    command: " + json.dumps(coverage_command) + "\n")
    yaml_text = re.sub(r"testing:\n.*?(?=\n#|\n[a-zA-Z_]+:|\Z)", testing, yaml_text, count=1, flags=re.S)
    atomic_write(yaml_path, yaml_text)
    now = dt.datetime.now(dt.timezone.utc).replace(microsecond=0).isoformat().replace("+00:00", "Z")
    about = f"""---
type: Context
title: {name}
description: {description}
resource: {description_source}
tags: [proyecto, contexto]
timestamp: {now}
agent: alex
confidence: 0.9
---

# {name}

## Qué es

{description}

## Estructura detectada

{', '.join(modules) if modules else 'Sin módulos principales detectados.'}

## Límites de la detección

El público, las prioridades y las decisiones de producto no se inventan. Alex debe
consultarlas al usuario cuando afecten el trabajo solicitado.
"""
    # The authoritative content is committed to TeamDB below; no implicit exports.

    style_files = find_style_files(project) if has_ui else []
    tokens, fonts = style_evidence(project, style_files)
    design = ""
    if has_ui:
        sources = "\n".join(f"- `{path.relative_to(project)}`" for path in style_files) or "- No se detectaron fuentes de estilo."
        token_lines = "\n".join(f"- `{token}`" for token in tokens) or "- No hay variables CSS consolidadas; preservar los estilos existentes antes de definir tokens."
        font_lines = "\n".join(f"- `{font}`" for font in fonts) or "- No se detectó `font-family`; verificar componentes y carga de fuentes antes de cambiar tipografía."
        design = f"""---
type: Concept
title: Sistema de diseño detectado
description: Evidencia visual extraída del código existente; no inventa una identidad nueva.
resource: código fuente del proyecto
tags: [design, ui, design-system]
timestamp: {now}
agent: alex
confidence: 0.8
---

# Sistema de diseño de {name}

## Regla principal

Preservar la interfaz existente. Antes de unificar estilos, identificar la fuente
canónica, comparar antes/después y pedir decisión al usuario si hay dos identidades válidas.

## Fuentes actuales

{sources}

## Tokens detectados

{token_lines}

## Tipografías detectadas

{font_lines}

## Restricciones

- No crear una hoja por componente si el proyecto usa estilos globales o tokens compartidos.
- No mezclar estilos globales, utilidades y valores literales sin justificar la frontera.
- Un cambio de tipografía, paleta o layout general es transversal y requiere plan y revisión visual.
"""


    return {
        "name": name,
        "description": description,
        "description_source": description_source,
        "framework": framework,
        "language": language,
        "modules": modules,
        "has_ui": has_ui,
        "style_files": len(style_files),
        "about": about,
        "design": design,
    }


def seed_database(db: Path, facts: dict, codegraph: str) -> str:
    ready = bool(facts["description"] and facts["modules"] and facts["description_source"] != "detección de stack")
    if facts["has_ui"] and (not facts["design"] or facts["style_files"] == 0):
        ready = False
    if codegraph == "failed":
        ready = False
    status = "initialized" if ready else "degraded"
    stack_body = f"language={facts['language']}; framework={facts['framework']}; modules={','.join(facts['modules'])}"
    conn = sqlite3.connect(db, timeout=5)
    try:
        conn.execute("BEGIN IMMEDIATE")
        concepts = [
            ("project-summary", facts["name"], facts["about"], "project-summary"),
            ("project-stack", "Stack y módulos detectados", stack_body, "stack"),
        ]
        if facts["design"]:
            concepts.append(("design-system", "Sistema de diseño detectado", facts["design"], "design-system"))
        for row in concepts:
            slug, title, body, category = row
            key = "bootstrap.generated." + slug
            existing = conn.execute("SELECT body_md FROM concepts WHERE slug=?", (slug,)).fetchone()
            previous = conn.execute("SELECT value FROM schema_meta WHERE key=?", (key,)).fetchone()
            current_hash = hashlib.sha256((existing[0] or "").encode()).hexdigest() if existing else None
            generated_hash = hashlib.sha256(body.encode()).hexdigest()
            managed = not existing or (previous and previous[0] == current_hash)
            if managed:
                conn.execute(
                    "INSERT INTO concepts(slug,title,body_md,category,updated_at) VALUES(?,?,?,?,datetime('now')) "
                    "ON CONFLICT(slug) DO UPDATE SET title=excluded.title,body_md=excluded.body_md,"
                    "category=excluded.category,updated_at=excluded.updated_at", row)
                conn.execute("INSERT INTO schema_meta(key,value) VALUES(?,?) ON CONFLICT(key) DO UPDATE SET value=excluded.value",
                             (key, generated_hash))
                conn.execute("DELETE FROM schema_meta WHERE key=?", ("bootstrap.pending." + slug,))
            else:
                # A human edit (or legacy row with unknown origin) wins. Keep a
                # separate observation for review rather than overwriting it.
                conn.execute("INSERT INTO schema_meta(key,value) VALUES(?,?) ON CONFLICT(key) DO UPDATE SET value=excluded.value",
                             ("bootstrap.pending." + slug, json.dumps({"title": title, "body": body, "reason": "existing-memory-preserved"}, ensure_ascii=False)))
        for key, value in (("project_readiness", status), ("codegraph_status", codegraph)):
            conn.execute(
                "INSERT INTO schema_meta(key,value) VALUES(?,?) ON CONFLICT(key) DO UPDATE SET value=excluded.value",
                (key, value),
            )
        conn.commit()
    except Exception:
        conn.rollback()
        raise
    finally:
        conn.close()
    return status


def pending_reviews(db: Path) -> list[str]:
    conn = sqlite3.connect(db)
    try:
        return [row[0].removeprefix("bootstrap.pending.") for row in
                conn.execute("SELECT key FROM schema_meta WHERE key LIKE 'bootstrap.pending.%' ORDER BY key")]
    finally:
        conn.close()


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--project", required=True)
    parser.add_argument("--codegraph", default="unavailable")
    args = parser.parse_args()
    project = Path(args.project).resolve()
    context = project / ".opencode/context"
    facts = write_context(project, context, project / ".opencode/project.yaml")
    status = seed_database(context / "team.db", facts, args.codegraph)
    print(json.dumps({"readiness": status, "concepts": 3 if facts["design"] else 2,
                      "style_files": facts["style_files"], "codegraph": args.codegraph,
                      "refresh_policy": "generated content refreshed; human/legacy content preserved",
                      "pending_review": pending_reviews(context / "team.db")}))
    return 0 if status == "initialized" else 3


if __name__ == "__main__":
    raise SystemExit(main())
