"""Regressões do contrato editorial; execute com unittest, sem rede ou cluster."""

import unittest

from pedagogia import chapter_errors, prose_lines


def chapter(body="Texto da aula.", references="- [Fonte](https://example.org) — aprofundamento opcional."):
    return (
        "# Aula\n\n## Antes de começar\n\nPré-requisitos.\n\n"
        "## O que você vai conseguir fazer\n\nObjetivo.\n\n"
        f"## Prática\n\n{body}\n\n## Fechamento\n\nSíntese.\n\n"
        f"## Referências opcionais\n\n{references}\n"
    )


def check(content):
    prose, unclosed = prose_lines(content)
    return chapter_errors(prose), unclosed


class PedagogyTests(unittest.TestCase):
    def test_valid_chapter_and_internal_link(self):
        self.assertEqual(check(chapter("Abra o [manifest](../laboratorios/exemplo.yaml).")), ([], False))

    def test_operational_urls_and_fake_headings_in_code_are_allowed(self):
        content = chapter(
            "Teste `curl https://example.org/healthz` e ``https://example.org``.\n\n"
            "```bash\ncurl https://example.org/download\n## Fechamento\n```"
        )
        self.assertEqual(check(content), ([], False))

    def test_inline_link_is_rejected(self):
        errors, _ = check(chapter("Leia [tudo](https://example.org/docs)."))
        self.assertTrue(any("link externo" in error for error in errors))

    def test_raw_url_is_rejected(self):
        errors, _ = check(chapter("Consulte https://example.org/docs."))
        self.assertTrue(any("link externo" in error for error in errors))

    def test_reference_link_in_body_is_rejected(self):
        errors, _ = check(chapter("Leia [a documentação][fonte].", "[fonte]: https://example.org/docs"))
        self.assertTrue(any("link externo" in error for error in errors))

    def test_missing_and_duplicate_sections(self):
        missing, _ = check(chapter().replace("## Antes de começar", "## Pré-requisitos"))
        duplicate, _ = check(chapter("## Antes de começar\n\nDuplicada."))
        self.assertTrue(any("exatamente uma vez" in error for error in missing))
        self.assertTrue(any("exatamente uma vez" in error for error in duplicate))

    def test_order_is_required(self):
        text = chapter().replace("## Antes de começar", "## TEMP")
        text = text.replace("## O que você vai conseguir fazer", "## Antes de começar")
        text = text.replace("## TEMP", "## O que você vai conseguir fazer")
        self.assertTrue(any("fora da ordem" in error for error in check(text)[0]))

    def test_references_are_last(self):
        errors, _ = check(chapter() + "\n## Mais uma prática obrigatória\n")
        self.assertTrue(any("última seção" in error for error in errors))

    def test_references_identify_a_source(self):
        errors, _ = check(chapter(references="Nenhuma fonte identificada."))
        self.assertTrue(any("ao menos uma fonte" in error for error in errors))

    def test_unclosed_fence_is_reported(self):
        _, unclosed = check(chapter() + "\n```bash\nprintf teste\n")
        self.assertTrue(unclosed)

    def test_fence_length_and_tildes(self):
        self.assertEqual(prose_lines("````text\n```\nhttps://example.org\n````\nFim"), ([(5, "Fim")], False))
        self.assertEqual(prose_lines("~~~bash\ncurl https://example.org\n~~~\nFim"), ([(4, "Fim")], False))


if __name__ == "__main__":
    unittest.main()
