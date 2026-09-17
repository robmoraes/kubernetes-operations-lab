# Kubernetes: da instalação à operação e arquitetura

Curso prático em português para quem domina Linux, containers, redes, DNS e TLS e quer trabalhar com Kubernetes em DevOps, SRE e arquitetura cloud. Você vai instalar o primeiro control plane manualmente, publicar e operar aplicações, diagnosticar falhas, recuperar dados e evoluir para HA, GitOps e EKS. CKA é a certificação principal; há prática complementar de CKAD e um projeto de portfólio.

Não é necessário conhecer outro orquestrador, ter uma aplicação própria ou acessar infraestrutura de uma empresa. Os laboratórios fornecem uma aplicação-base e os componentes usados ao longo da trilha. Você também pode aplicar o aprendizado a um projeto próprio containerizado, mantendo o mesmo rigor de validação.

**Comece por [00 — Como estudar](curso/00-como-estudar.md), depois siga [01 — Primeiro control plane](curso/01-control-plane.md).** Reserve aproximadamente 240–320 horas, distribuídas conforme seu tempo livre e fins de semana. Avance quando comprovar os resultados, não apenas quando terminar a leitura.

## Como usar este repositório

1. Leia o [plano de estudo](CURSO.md) e prepare um laboratório dedicado.
2. Execute o laboratório guiado do módulo, explicando cada resultado.
3. Faça o desafio autônomo e o exercício de falha/recuperação.
4. Guarde evidências sanitizadas e atualize [seu progresso](PROGRESSO.md).
5. Complete os [simulados](avaliacoes/README.md) e o projeto final.

Cada aula tem um percurso fechado: pré-requisitos e objetivos → explicação e exemplos → prática guiada → falha/recuperação → desafio → fechamento. O conhecimento necessário para seus objetivos está nela ou nos módulos anteriores declarados. **As referências externas ficam no final e são opcionais:** não é preciso abri-las para concluir a aula. Arquivos locais dos laboratórios são material de prática, e URLs em comandos são downloads ou testes, não tarefas de leitura.

Os comandos indicam a máquina/contexto; comandos de instalação ou recuperação alteram o laboratório. Não aplique recursivamente toda a pasta `laboratorios/`: ela contém alternativas, exemplos parametrizados e falhas intencionais. Siga a ordem de cada aula; o [índice dos laboratórios](laboratorios/README.md) serve para localizar os arquivos, não como roteiro adicional obrigatório.

## Trilha

| Módulo                                          | Você será capaz de…                                                   |
| ----------------------------------------------- | --------------------------------------------------------------------- |
| [00 — Preparação](curso/00-como-estudar.md)     | Inventariar uma aplicação e planejar laboratório, agenda e custos      |
| [01 — Control plane](curso/01-control-plane.md) | Instalar kubeadm/containerd/CNI e ingressar workers manualmente       |
| [02 — Workloads](curso/02-workloads.md)         | Publicar aplicações, configurar probes e fazer rollback               |
| [03 — Rede](curso/03-rede.md)                   | Operar Services, DNS, Traefik, Ingress e Gateway API                  |
| [04 — Storage](curso/04-storage.md)             | Usar PVC/PV/CSI e explicar EBS, persistência e restrições de zona     |
| [05 — Scheduling](curso/05-scheduling.md)       | Controlar recursos, placement, manutenção e autoscaling               |
| [06 — Segurança](curso/06-seguranca.md)         | Aplicar RBAC, segurança de Pods e NetworkPolicy com testes            |
| [07 — Diagnóstico](curso/07-troubleshooting.md) | Isolar e corrigir falhas de aplicação, rede, runtime e nós            |
| [08 — Manutenção](curso/08-manutencao.md)       | Executar backup/restore, inspecionar certificados e ensaiar upgrade   |
| [09 — Entrega](curso/09-entrega.md)             | Empacotar, versionar e reconciliar aplicações por GitOps              |
| [10 — HA](curso/10-alta-disponibilidade.md)     | Expandir o control plane, testar quórum e defender decisões multi-AZ  |
| [11 — EKS](curso/11-eks.md)                     | Provisionar por IaC e operar identidade, rede e add-ons AWS           |
| [12 — SRE e projeto final](curso/12-sre.md)     | Definir SLO, responder a incidentes e apresentar um portfólio técnico |

## Avaliação e portfólio

- [Mapa CKA/CKAD e critérios para agendar](avaliacoes/certificacoes.md).
- [Simulado A](avaliacoes/simulado-a.md): recursos e troubleshooting, 120 minutos.
- [Simulado B](avaliacoes/simulado-b.md): administração e recuperação, 120 minutos.
- [Complemento CKAD](avaliacoes/ckad-complementar.md): aplicações, configuração e estratégias de entrega.
- [Evidências](evidencias/README.md) e modelos de [diário](templates/diario.md), [ADR](templates/adr.md), [runbook](templates/runbook.md) e [postmortem](templates/postmortem.md).

O objetivo é demonstrar competência executando, diagnosticando e justificando escolhas. Simulados são autorais, não questões reais; a conclusão não substitui experiência de produção nem garante aprovação em uma prova.

## Ambiente e referências

Base didática: Ubuntu Server 24.04 AMD64, containerd e Kubernetes 1.35 com kubeadm. Essa minor corresponde à versão anunciada na página oficial CKA consultada nesta edição, não a uma recomendação automática da versão mais nova. Os capítulos ensinam a selecionar e registrar as versões usadas, sem exigir pesquisa externa na primeira execução. O catálogo de [fontes e versões](referencias/fontes-e-versoes.md) é uma referência opcional para aprofundamento ou manutenção do curso, não uma leitura prévia obrigatória.

Comece com 1 control plane e 2 workers na mesma AZ. A primeira criação e destruição são manuais; depois, o Terraform de apoio pode reconstruir a base entre sessões para evitar recursos cobrados ociosos. O módulo 08 usa um **cluster auxiliar separado** para restore e upgrade; inclua seus hosts e discos no orçamento da janela. No capítulo HA, expanda a reconstrução corrente conforme a aula; no EKS, crie outro ambiente separado e faça a limpeza instruída. O disco root gp3 da EC2 existe antes do Kubernetes; volumes solicitados por PVC são assunto do módulo 04. A disponibilidade regional, custos e limites dependem da conta AWS.

A instalação segue o [procedimento manual do módulo 01](curso/01-control-plane.md); a automação posterior preserva a mesma fronteira de aprendizado. Comparações com outras plataformas ficam em [extras](extras/README.md), fora da rota obrigatória e dos critérios de aprovação. As [notas anteriores](referencias/bootstrap-original.md) estão preservadas apenas como histórico, não devem ser executadas.

## Verificação local do material

Com Python 3, PyYAML e make disponíveis:

```bash
make check
```

Se PyYAML faltar, instale apenas no ambiente virtual do repositório:

```bash
python3 -m venv .venv
.venv/bin/python -m pip install PyYAML==6.0.2
.venv/bin/python -m unittest discover -s scripts -p 'test_*.py'
.venv/bin/python scripts/verificar-curso.py
```

O verificador inspeciona arquivos e destinos de links locais, blocos de código fechados, YAML/JSON e sintaxe dos scripts. Também exige as quatro seções do contrato editorial nos 13 módulos e detecta links externos de leitura antes das referências opcionais. Os testes de regressão conferem essas regras, incluindo a distinção entre leitura e URLs operacionais em código.

Templates Helm são verificados por `helm lint/template` na aula 09; Terraform tem seus próprios comandos na aula 11. A checagem offline não cria EC2, acessa kubeconfig nem executa os exercícios. Ela não substitui revisão pedagógica, validação de schema pelo servidor ou testes de aceitação em cluster.

Consulte o [registro de validação e seus limites](referencias/validacao-do-material.md) para saber o que já foi conferido nesta edição.

Para editar ou ampliar o curso, siga a [especificação pedagógica](SPEC-PEDAGOGICA.md). Ela é um contrato para quem mantém o material; o aluno não precisa lê-la para começar.
