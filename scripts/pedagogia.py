"""Regras editoriais offline; não avaliam domínio técnico ou qualidade da aula."""

import re

SECTIONS = (
    "Antes de começar",
    "O que você vai conseguir fazer",
    "Fechamento",
    "Referências opcionais",
)


def prose_lines(content):
    """Retorna prosa numerada, ignorando blocos fenced, e fechamento pendente."""
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
    return prose, fence is not None


def without_inline_code(line):
    return re.sub(r"(`+).*?\1", "", line)


def chapter_errors(prose):
    """Verifica contrato de seções e links externos de leitura no corpo."""
    errors = []
    headings = [(number, line[3:].strip()) for number, line in prose if line.startswith("## ")]
    positions = {}
    for section in SECTIONS:
        matches = [number for number, title in headings if title == section]
        if len(matches) != 1:
            errors.append(f"seção '## {section}' deve aparecer exatamente uma vez")
        if matches:
            positions[section] = matches[0]

    if len(positions) == len(SECTIONS):
        order = [positions[section] for section in SECTIONS]
        if order != sorted(order):
            errors.append("seções do contrato pedagógico fora da ordem esperada")

    references_start = positions.get(SECTIONS[-1], float("inf"))
    if any(number > references_start for number, _ in headings):
        errors.append("Referências opcionais deve ser a última seção de nível 2")

    external_definitions = set()
    for _, line in prose:
        match = re.match(r"^\s*\[([^\]]+)\]:\s*<?https?://", line, re.IGNORECASE)
        if match:
            external_definitions.add(match.group(1).strip().casefold())

    for number, line in prose:
        if number >= references_start:
            continue
        readable = without_inline_code(line)
        external = bool(re.search(r"https?://", readable, re.IGNORECASE))
        # Inclui links Markdown por referência, mesmo que a definição esteja no fim.
        references = re.findall(r"\[([^\]]+)\]", readable)
        external = external or any(ref.strip().casefold() in external_definitions for ref in references)
        if external:
            errors.append(
                f"linha {number}: link externo de leitura antes de Referências opcionais; "
                "URLs operacionais pertencem a código inline ou blocos de código"
            )

    if references_start != float("inf") and not any(
        number > references_start and re.search(r"https?://", line, re.IGNORECASE)
        for number, line in prose
    ):
        errors.append("Referências opcionais precisa identificar ao menos uma fonte externa")
    return errors
