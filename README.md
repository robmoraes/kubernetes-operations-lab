# Kubernetes: do Swarm à operação e arquitetura

Curso prático em português para quem já opera Docker Swarm em escala e quer trabalhar com Kubernetes em DevOps, SRE e arquitetura cloud. Você vai instalar o primeiro control plane manualmente, migrar uma aplicação, diagnosticar falhas, recuperar dados e evoluir para HA, GitOps e EKS. CKA é a certificação principal; há prática complementar de CKAD e um projeto de portfólio.

**Comece por [00 — Como estudar](curso/00-como-estudar.md), depois siga [01 — Primeiro control plane](curso/01-control-plane.md).** Reserve aproximadamente 240–320 horas, distribuídas conforme seu tempo livre e fins de semana. Avance quando comprovar os resultados, não apenas quando terminar a leitura.

## Como usar este repositório

1. Leia o [plano de estudo](CURSO.md) e prepare um laboratório dedicado.
2. Execute o laboratório guiado do módulo, explicando cada resultado.
3. Faça o desafio autônomo e o exercício de falha/recuperação.
4. Guarde evidências sanitizadas e atualize [seu progresso](PROGRESSO.md).
5. Complete os [simulados](avaliacoes/README.md) e o projeto final.

Cada aula combina explicação, comandos, falhas observáveis e critérios de aprovação. Os comandos indicam a máquina/contexto; comandos de instalação ou recuperação alteram o laboratório. Não aplique recursivamente toda a pasta `laboratorios/`: ela contém alternativas, exemplos parametrizados e falhas intencionais. Siga a ordem de cada aula e consulte o [índice dos laboratórios](laboratorios/README.md).

## Trilha

| Módulo                                          | Você será capaz de…                                                   |
| ----------------------------------------------- | --------------------------------------------------------------------- |
| [00 — Preparação](curso/00-como-estudar.md)     | Montar o laboratório, registrar versões e controlar custos            |
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

Base didática: Ubuntu Server 24.04 ARM64, containerd e Kubernetes 1.35 com kubeadm. Essa minor corresponde à versão anunciada na página oficial CKA consultada nesta edição, não a uma recomendação automática da versão mais nova. Os capítulos mostram como selecionar patches/versões e verificar compatibilidade. Consulte [fontes e versões](referencias/fontes-e-versoes.md) antes de instalar.

Comece com 1 control plane e 2 workers na mesma AZ. No capítulo HA, expanda temporariamente; no EKS, crie um ambiente separado e faça a limpeza instruída. O disco root gp3 da EC2 existe antes do Kubernetes; volumes solicitados por PVC são assunto do módulo 04. A disponibilidade regional, custos e limites dependem da conta AWS.

A [ponte Swarm → Kubernetes](referencias/swarm-para-kubernetes.md) esclarece diferenças sem repetir Linux e redes. O [bootstrap existente](bootstrap-kubernetes-arm64.sh) foi preservado como material para comparação e automação posterior; **ele não é o roteiro inicial, não foi validado em um host ARM nesta edição e não deve ser executado sobre um cluster já em uso**. As [notas anteriores](referencias/bootstrap-original.md) estão preservadas como histórico.

## Verificação local do material

Com Python 3, PyYAML e make disponíveis:

```bash
make check
```

Se PyYAML faltar, instale apenas no ambiente virtual do repositório:

```bash
python3 -m venv .venv
.venv/bin/python -m pip install PyYAML==6.0.2
.venv/bin/python scripts/verificar-curso.py
```

O verificador inspeciona arquivos e destinos de links locais, blocos de código fechados, YAML/JSON e sintaxe dos scripts. Templates Helm são verificados por `helm lint/template` na aula 09; Terraform tem seus próprios comandos na aula 11. A checagem offline não cria EC2, acessa kubeconfig nem executa os exercícios. Ela também não substitui validação de schema pelo servidor ou os testes de aceitação em cluster.

Consulte o [registro de validação e seus limites](referencias/validacao-do-material.md) para saber o que já foi conferido nesta edição.
