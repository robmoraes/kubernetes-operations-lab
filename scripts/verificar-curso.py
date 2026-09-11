#!/usr/bin/env python3
"""Verificação offline; não acessa cluster/AWS nem executa comandos das aulas."""

from pathlib import Path
import json
import re
import subprocess
import sys
from urllib.parse import unquote, urlsplit

try:
    import yaml
except ImportError:
    sys.exit("Falta PyYAML. Instale a dependência conforme README.md e repita.")

ROOT = Path(__file__).resolve().parents[1]
IGNORED = {".git", ".terraform", ".venv", "node_modules", ".local", "__pycache__"}
errors = []
counts = {"markdown": 0, "links": 0, "yaml": 0, "json": 0, "shell": 0}
templates = []


class UniqueLoader(yaml.SafeLoader):
    """Rejeita chaves duplicadas em vez de perder valores silenciosamente."""


def unique_mapping(loader, node, deep=False):
    result = {}
    for key_node, value_node in node.value:
        key = loader.construct_object(key_node, deep=deep)
        if key in result:
            raise ValueError(f"chave YAML duplicada {key!r}, linha {key_node.start_mark.line + 1}")
        result[key] = loader.construct_object(value_node, deep=deep)
    return result


UniqueLoader.add_constructor(yaml.resolver.BaseResolver.DEFAULT_MAPPING_TAG, unique_mapping)


def fail(path, message):
    errors.append(f"{path.relative_to(ROOT)}: {message}")


def check_markdown(path, content):
    counts["markdown"] += 1
    fence = None
    prose = []
    for number, line in enumerate(content.splitlines(), 1):
        marker = re.match(r"^\s*(`{3,}|~{3,})(.*)$", line)
        if marker:
            token, rest = marker.groups()
            if fence is None:
                fence = (token[0], len(token))
            elif token[0] == fence[0] and len(token) >= fence[1] and not rest.strip():
                fence = None
            continue
        if fence is None:
            prose.append((number, line))
    if fence:
        fail(path, "bloco de código sem fechamento")
    for number, line in prose:
        for target in re.findall(r"\[[^\]\n]+\]\(([^)\n]+)\)", line):
            target = target.strip()
            if target.startswith("<"):
                target = target.split(">", 1)[0][1:]
            else:
                target = target.split(' "', 1)[0]
            parsed = urlsplit(target)
            if parsed.scheme or parsed.netloc or not parsed.path:
                continue
            destination = (path.parent / unquote(parsed.path)).resolve()
            counts["links"] += 1
            if not destination.exists():
                fail(path, f"linha {number}: link local inexistente: {target}")


for path in sorted(ROOT.rglob("*")):
    if not path.is_file() or any(part in IGNORED for part in path.relative_to(ROOT).parts):
        continue
    suffix = path.suffix.lower()
    if suffix not in {".md", ".yaml", ".yml", ".json", ".sh"}:
        continue
    content = path.read_text(encoding="utf-8")
    if suffix == ".md":
        check_markdown(path, content)
    elif suffix in {".yaml", ".yml"}:
        is_helm_template = "templates" in path.relative_to(ROOT).parts and any(
            (parent / "Chart.yaml").is_file() for parent in path.parents if parent != ROOT.parent
        )
        if is_helm_template:
            templates.append(str(path.relative_to(ROOT)))
            continue
        try:
            documents = list(yaml.load_all(content, Loader=UniqueLoader))
            if not documents or all(document is None for document in documents):
                fail(path, "arquivo YAML vazio")
            counts["yaml"] += len(documents)
        except (yaml.YAMLError, ValueError, TypeError) as exc:
            fail(path, str(exc))
    elif suffix == ".json":
        try:
            json.loads(content)
            counts["json"] += 1
        except json.JSONDecodeError as exc:
            fail(path, str(exc))
    elif suffix == ".sh":
        result = subprocess.run(["bash", "-n", str(path)], capture_output=True, text=True)
        counts["shell"] += 1
        if result.returncode:
            fail(path, result.stderr.strip())

expected_modules = [
    "00-como-estudar", "01-control-plane", "02-workloads", "03-rede", "04-storage",
    "05-scheduling", "06-seguranca", "07-troubleshooting", "08-manutencao",
    "09-entrega", "10-alta-disponibilidade", "11-eks", "12-sre",
]
for module in expected_modules:
    if not (ROOT / "curso" / f"{module}.md").is_file():
        errors.append(f"módulo ausente: curso/{module}.md")

if errors:
    print("Falhas:\n" + "\n".join(f"- {error}" for error in errors))
    sys.exit(1)

print("OK — " + ", ".join(f"{total} {kind}" for kind, total in counts.items()))
if templates:
    print("Templates Helm exigem helm lint/template; não foram tratados como YAML pronto:")
    print("\n".join(f"- {template}" for template in templates))
print("Não valida schemas Kubernetes, disponibilidade de imagens, permissões AWS ou comportamento em cluster.")
