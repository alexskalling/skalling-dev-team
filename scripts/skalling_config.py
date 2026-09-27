"""Lectura única de la configuración de tests de .opencode/project.yaml.

La usan el motor (skalling-workflow.py), skalling-verify.sh,
skalling-project-config.py y el bootstrap. Antes cada uno tenía su propio
parser por regex y ninguno desempaquetaba bien los escalares YAML: un comando
como  "python3 -c \\"print(42)\\""  quedaba con barras literales y Bash fallaba
(tercera auditoría, sobre e95a388). Sin PyYAML (el plugin corre con el python3
del sistema): se interpreta el subconjunto que usa project.yaml.
"""
import json
import re
from pathlib import Path

TESTING_KINDS = ('unit', 'fast', 'integration', 'e2e', 'coverage')


def scalar(raw):
    """Valor de un escalar YAML de una línea: "doble" (con escapes), 'simple'
    ('' es una comilla) o plano (sin el comentario # final)."""
    value = raw.strip()
    if value.startswith('"'):
        end = _closing_double_quote(value)
        # Malformado (sin cierre o con texto después): nunca a medias. Cortar
        # en la primera comilla convertía "bash -c "$(x)"" en "bash -c ".
        if end is None or not re.fullmatch(r'\s*(#.*)?', value[end + 1:]):
            return None
        try:
            return json.loads(value[:end + 1])
        except ValueError:
            return None
    if value.startswith("'"):
        match = re.match(r"'((?:[^']|'')*)'(.*)$", value)
        if not match or not re.fullmatch(r'\s*(#.*)?', match.group(2)):
            return None
        return match.group(1).replace("''", "'")
    return re.sub(r'\s+#.*$', '', value).strip()


def _closing_double_quote(value):
    escaped = False
    for index, char in enumerate(value[1:], start=1):
        if escaped:
            escaped = False
        elif char == '\\':
            escaped = True
        elif char == '"':
            return index
    return None


def testing_config(path):
    """{'unit': cmd, 'fast': cmd, ..., 'timeout_seconds': int} con solo los
    comandos disponibles (available: true y no vacíos)."""
    path = Path(path)
    if not path.is_file():
        return {}
    text = path.read_text(encoding='utf-8')
    config = {}
    for kind in TESTING_KINDS:
        match = re.search(r'(?m)^[ \t]+' + kind + r':[ \t]*\n((?:[ \t]{3,}\S.*\n?)*)', text)
        block = match.group(1) if match else ''
        available = re.search(r'(?m)^\s*available:\s*(.*)$', block)
        command = re.search(r'(?m)^\s*command:\s*(.*)$', block)
        if available and (scalar(available.group(1)) or '').lower() == 'true' and command:
            value = scalar(command.group(1))
            if value:
                config[kind] = value
    timeout = re.search(r'(?m)^[ \t]+timeout_seconds:\s*(.*)$', text)
    if timeout and (scalar(timeout.group(1)) or '').isdigit():
        config['timeout_seconds'] = int(scalar(timeout.group(1)))
    return config


def yaml_quote(value):
    """Escalar YAML entre comillas dobles que scalar() vuelve a leer igual."""
    return json.dumps(value, ensure_ascii=False)


if __name__ == '__main__':
    # skalling-verify.sh: imprime el comando a correr (fast no; unit).
    import sys
    print(testing_config(sys.argv[1]).get(sys.argv[2] if len(sys.argv) > 2 else 'unit', ''))
