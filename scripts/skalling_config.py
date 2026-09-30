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
    config, blocks = {}, {}
    in_testing, kind, kind_indent = False, None, None
    timeout_value = None
    for line in text.splitlines():
        if not line.strip() or line.lstrip().startswith('#'):
            continue
        indent = len(line) - len(line.lstrip(' '))
        field = re.match(r'\s*([\w-]+):\s*(.*)$', line)
        if indent == 0:
            in_testing = bool(field and field[1] == 'testing' and not field[2])
            kind, kind_indent = None, None
            continue
        if not in_testing or not field:
            continue
        key, raw = field.groups()
        if key in TESTING_KINDS and not raw:
            kind, kind_indent = key, indent
            blocks[kind] = {}
        elif key == 'timeout_seconds' and (kind_indent is None or indent <= kind_indent):
            timeout_value = scalar(raw)
            kind = None
        elif kind is not None and indent > kind_indent:
            if key in {'command', 'available'}:
                blocks[kind][key] = scalar(raw)
        elif kind_indent is not None and indent <= kind_indent:
            kind = None
    for kind, block in blocks.items():
        value = block.get('command')
        if (block.get('available') or '').lower() == 'true' and value and value not in {'|', '>', '|-', '>-'}:
            config[kind] = value
    if timeout_value and timeout_value.isdigit():
        config['timeout_seconds'] = int(timeout_value)

    return config


def yaml_quote(value):
    """Escalar YAML entre comillas dobles que scalar() vuelve a leer igual."""
    return json.dumps(value, ensure_ascii=False)


if __name__ == '__main__':
    # skalling-verify.sh: imprime el comando a correr (fast no; unit).
    import sys
    print(testing_config(sys.argv[1]).get(sys.argv[2] if len(sys.argv) > 2 else 'unit', ''))
