# Especificação — capítulos com começo, meio e fim

## Problema e resultado esperado

O aluno precisa conseguir estimar e concluir uma aula sem descobrir, durante a leitura, uma cadeia de leituras externas obrigatórias. A revisão preserva a trilha de Kubernetes, os laboratórios e o rigor técnico, mas torna explícito o contrato de cada capítulo: o que se presume conhecido, o que será ensinado, o que será praticado e como comprovar a conclusão.

Autossuficiência vale para os objetivos anunciados e os pré-requisitos declarados; não significa explicar toda a área em uma aula. Documentação profissional continua importante, mas consultar um campo específico é diferente de receber a tarefa indefinida de estudar um site inteiro.

## Escopo

- Revisar os módulos 00–12, a apresentação e o plano de estudo.
- Preencher lacunas de teoria e de procedimentos necessários, em vez de apenas deslocar links.
- Preservar versões-base, topologia, nomes de objetos, caminhos dos laboratórios, avaliações e proteções de segurança, salvo correção técnica justificada.
- Acrescentar exemplos locais quando um desafio exigir um mecanismo ainda não demonstrado.
- Verificar a estrutura editorial automaticamente e revisar a coerência pedagógica manualmente.

Não faz parte desta revisão provisionar infraestrutura, executar falhas em clusters, recriar o bootstrap removido, converter o curso em uma enciclopédia ou mudar sua trilha de certificação. Arquivos históricos e catálogos de fontes continuam sendo referências, não aulas obrigatórias.

## Contrato de cada capítulo

Cada arquivo em `curso/` terá estas quatro seções reconhecíveis, além das seções de explicação e prática:

1. `## Antes de começar`: conhecimentos anteriores, ambiente, ferramentas, materiais locais e limites do laboratório. Uma instalação nova necessária deve ser ensinada antes do primeiro uso ou ter sido concluída em um pré-requisito indicado.
2. `## O que você vai conseguir fazer`: resultados observáveis e delimitados. O módulo 00 avalia preparação, não administração de um cluster que ainda não existe.
3. `## Fechamento`: síntese, perguntas ou verificações de compreensão e critério claro para avançar. Leitura concluída não equivale a prática dominada.
4. `## Referências opcionais`: última seção, com fontes externas identificadas e uma frase sobre o que cada fonte aprofunda. Nenhuma delas bloqueia a conclusão da aula.

O percurso entre a abertura e o fechamento deve apresentar conceito, exemplo explicado, prática guiada, resultado esperado, falha/recuperação e desafio independente, quando aplicáveis. Os títulos intermediários podem variar para preservar a narrativa; não é necessário repetir um formulário em cada parágrafo.

## Regras de conteúdo e navegação

- Conhecimento indispensável fica na aula ou em um pré-requisito interno declarado, não atrás de uma referência externa.
- Termos novos necessários são explicados antes de serem cobrados. Os mecanismos do Kubernetes são ensinados diretamente; comparações com outros orquestradores ficam em `extras/`, sem dependência na rota principal.
- Links externos de leitura ficam exclusivamente em `Referências opcionais`. Links para módulos prévios, manifests e templates locais podem aparecer no ponto de uso, com seu papel explicado.
- URLs operacionais em comandos e configurações — repositórios de pacotes, registries, endpoints, downloads e testes HTTP — permanecem junto ao procedimento. Acesso de rede para executar um laboratório não é uma obrigação de leitura externa.
- Manifests extensos de fornecedores podem ser baixados: a aula deve explicar sua finalidade, versão, impacto e verificação, sem exigir estudar todo o projeto upstream.
- Uma consulta técnica como exercício informa a pergunta, a ferramenta/fonte, o recorte e a condição de término. Prefira `kubectl explain`, ajuda local e saídas do próprio laboratório. Pesquisa externa de aprofundamento é explicitamente opcional.
- Segurança, autenticação, seleção de versões e limpeza não podem ser omitidas nem delegadas a um genérico “siga a documentação”. Casos fora do ambiente suportado são declarados como adaptações fora do laboratório guiado.
- Conteúdo avançado opcional não pode esconder uma competência exigida pela rubrica. Não reduzir os objetivos essenciais para fazer um capítulo parecer completo.
- Preserve comandos de observação, evidências sanitizadas, rollback e limites entre laboratório e produção. Não publique segredos ou atribua validações em cluster que não foram realizadas.

## Critérios de aceitação

- A trilha pode ser concluída por quem conhece Linux, containers, redes, DNS e TLS, sem experiência em outro orquestrador, aplicação própria ou acesso a ambiente corporativo.
- Inventário, desafios e projeto final aceitam os materiais fornecidos ou uma aplicação própria containerizada. A origem da aplicação não altera os critérios de aprovação; todos os caminhos exercitam estado, rede, entrega, diagnóstico e recuperação nas etapas correspondentes.
- Extras comparativos são opcionais e não contêm conhecimento indispensável ausente das aulas. Registros pessoais históricos não são reescritos para acompanhar mudanças editoriais.
- Os 13 módulos têm abertura, objetivos, fechamento e referências opcionais finais.
- Não existem links externos de leitura no corpo obrigatório das aulas.
- Instalações, exemplos e pré-requisitos aparecem antes das tarefas que dependem deles.
- Desafios cobram mecanismos previamente explicados e praticados; a autonomia cresce por variações e combinações, não por omissão de instruções básicas.
- Referências indicam o ganho de aprofundamento, sem “leia tudo”, “consulte antes de continuar” ou obrigação implícita.
- Cada aula permite responder: “O que aprendi? Como comprovo? O que ainda está fora do escopo?”
- `make check` e `git diff --check` passam. Novos exemplos recebem validação proporcional: sintaxe e estrutura offline, com limites registrados.
- Uma revisão humana/editorial verifica lacunas de conteúdo, coerência entre aula e laboratório e manutenção dos cuidados operacionais. A checagem estrutural não certifica qualidade pedagógica nem execução real.

## Ordem de implementação

1. Registrar este contrato e identificar dependências escondidas.
2. Reeditar fundamentos, rede/storage/scheduling, operação e plataforma em frentes separadas, seguindo o mesmo contrato.
3. Ajustar a apresentação do curso e o verificador; conferir pré-requisitos entre módulos.
4. Revisar o conjunto, executar checagens offline e registrar resultados e limitações.

Esta especificação orienta a edição do curso. O aluno não precisa lê-la para começar a estudar.

## Registro da implementação

Revisão aplicada em **12/09/2026** aos módulos 00–12, apresentação, plano e materiais de apoio envolvidos. O verificador passou a proteger o contrato de seções e a localização dos links de leitura, com testes de regressão. O [registro de validação](referencias/validacao-do-material.md) descreve evidências, correções técnicas e limites: não houve execução dos laboratórios em infraestrutura real.

Revisões futuras devem repetir os critérios acima. Um capítulo passar no verificador não demonstra, sozinho, que sua explicação é suficiente; dúvidas recorrentes do aluno e testes funcionais podem revelar novos ajustes necessários.

Em **12/09/2026**, o escopo foi ampliado para uma trilha independente da experiência prévia em outros orquestradores. A apresentação, os exercícios de entrada e entrega e o projeto final passam a admitir o percurso integral com os materiais locais, mantendo aplicações próprias como alternativa. Comparações foram isoladas nos extras; o nome do repositório e seu histórico Git foram mantidos.
