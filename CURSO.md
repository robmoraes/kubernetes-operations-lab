# Plano de estudo e critérios de avanço

Este curso parte da experiência de operar mais de 100 serviços em Docker Swarm. Linux, redes, DNS, TLS e containers são conhecimentos de entrada. A prioridade é aprender a API do Kubernetes, seus controllers, o agendamento e a operação do cluster. Uma pessoa experiente em Swarm já trabalha de forma declarativa: o salto aqui é conhecer novos recursos, relações e modos de falha.

## Ritmo e método

Reserve aproximadamente **240–320 horas**, incluindo repetições e projeto final. A 18–22 horas por semana, planeje cerca de 14–18 semanas; ajuste pelo desempenho, não pelo calendário. O cronograma anterior de 12 semanas é uma possibilidade intensiva, não uma obrigação.

Uma sessão de duas horas: 20 minutos de leitura, 70 de terminal, 20 de diagnóstico/variação e 10 de registro. No fim de semana, reserve um bloco de 4 horas para um desafio sem roteiro e outro para recuperação/documentação. A cada três módulos, refaça um laboratório antigo sem consultar sua solução.

Faça cada laboratório em três passagens:

1. **Guiada:** leia, antecipe o resultado, execute, observe a API e os logs.
2. **Autônoma:** parta do enunciado, escreva os manifests e use a documentação oficial.
3. **Operacional:** provoque a falha indicada, identifique a causa e recupere medindo tempo e impacto.

Consultar documentação faz parte da competência. Copiar um comando sem explicar o efeito não conta como conclusão. Ajuda de um tutor é útil na passagem guiada; nas avaliações, tente primeiro e peça uma pista, não a solução inteira.

## Sequência

| Etapa | Estudo e prática | Evidência necessária |
|---|---|---|
| 00 | [Como estudar](curso/00-como-estudar.md) | Inventário do lab, agenda, critérios de custo e registro de versões |
| 01 | [Control plane manual](curso/01-control-plane.md) | 1 CP + 2 workers, CNI saudável e explicação dos static Pods |
| 02 | [Workloads](curso/02-workloads.md) | App, probes, configuração, atualização e rollback |
| 03 | [Rede](curso/03-rede.md) | DNS, Services, Traefik, Ingress e Gateway API testados |
| 04 | [Storage](curso/04-storage.md) | Dado sobrevive à recriação; limitações de zona demonstradas |
| 05 | [Scheduling](curso/05-scheduling.md) | Requests/limits, distribuição, drain e autoscaling explicados |
| 06 | [Segurança](curso/06-seguranca.md) | RBAC mínimo e tráfego permitido/bloqueado comprovados |
| 07 | [Troubleshooting](curso/07-troubleshooting.md) | Incidentes diagnosticados por evidências, sem reinstalar |
| 08 | [Manutenção](curso/08-manutencao.md) | Backup restaurado, upgrade ensaiado e certificados inspecionados |
| 09 | [Entrega](curso/09-entrega.md) | Helm/Kustomize, GitOps, drift e rollback por Git |
| 10 | [Alta disponibilidade](curso/10-alta-disponibilidade.md) | Quórum, endpoint de API e recuperação de falha de CP |
| 11 | [EKS](curso/11-eks.md) | IaC, identidade, rede e storage gerenciados; custos inventariados |
| 12 | [SRE e projeto final](curso/12-sre.md) | SLO, alertas, runbooks, incidente e defesa de arquitetura |
| Avaliação | [Certificações](avaliacoes/certificacoes.md) e [simulados](avaliacoes/README.md) | Notas, tempos e lacunas registradas |

## Marcos profissionais

**Marco 1 — Publicar e explicar (00–03).** Você consegue traduzir um serviço do Swarm para Deployment + Service, explicar quem recria um Pod e diagnosticar o caminho cliente → Traefik → Service → Pod. Não se limite à aplicação de exemplo: migre um serviço seu sem dados de produção.

**Marco 2 — Operar (04–08).** Você distingue falha de aplicação, scheduler, CNI, CSI e control plane; recupera dados e faz manutenção com uma sequência verificada. Complete o simulado A depois do módulo 09, que fornece os exercícios de empacotamento usados na avaliação.

**Marco 3 — Projetar (09–12).** Você defende escolhas de disponibilidade, acesso, custo e operação. Complete o simulado B e o projeto final. Explique o que muda entre cluster manual e EKS, sem assumir que uma configuração de um funciona no outro.

## Aprovação de um módulo

A rubrica específica de cada capítulo é a referência. Para marcar o módulo concluído, entregue o laboratório, o desafio autônomo e evidência de recuperação. Registre as ajudas recebidas. Se passou pelo roteiro mas não consegue repetir o desafio, marque **em prática**.

O projeto final usa rubrica de 100 pontos no módulo 12. A meta interna dos simulados é **80/100 em duas tentativas independentes**, sem falhas críticas de contexto, perda de dados ou permissões excessivas. Isso é um critério de treino do curso, não a nota oficial de uma prova nem garantia de contratação.

## O que fica para depois

Desenvolver um operator próprio, service mesh, eBPF profundo, múltiplos clusters e CKS completa são especializações posteriores. Você aprenderá a instalar e usar CRDs/operators e a diagnosticá-los, sem precisar escrever um controller para publicar a primeira aplicação. Rancher e Portainer podem entrar como exercício adicional depois do marco operacional.

Use [PROGRESSO.md](PROGRESSO.md) a cada sessão. Comece agora pelo [módulo 00](curso/00-como-estudar.md).
