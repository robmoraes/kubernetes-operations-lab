# Plano de estudo e critérios de avanço

Este curso exige fundamentos de Linux, redes, DNS, TLS e containers. A prioridade é aprender a API do Kubernetes, seus controllers, o agendamento e a operação do cluster. Estado desejado, reconciliação e responsabilidades dos recursos são explicados diretamente, sem exigir experiência anterior em orquestração.

O percurso pode ser concluído com a aplicação-base e os componentes fornecidos nos laboratórios. Uma aplicação própria, executada com Compose, Docker ou outro ambiente, é uma alternativa para contextualizar o projeto. Sua origem não altera os critérios de aprovação. Não é necessário acessar produção nem desenvolver software para começar; comparações entre plataformas ficam nos [extras opcionais](extras/README.md).

## Ritmo e método

Reserve aproximadamente **240–320 horas**, incluindo repetições e projeto final. A 18–22 horas por semana, planeje cerca de 14–18 semanas; ajuste pelo desempenho, não pelo calendário. O cronograma anterior de 12 semanas é uma possibilidade intensiva, não uma obrigação.

Uma sessão de duas horas: 20 minutos de leitura, 70 de terminal, 20 de diagnóstico/variação e 10 de registro. No fim de semana, reserve um bloco de 4 horas para um desafio sem roteiro e outro para recuperação/documentação. A cada três módulos, refaça um laboratório antigo sem consultar sua solução.

Faça cada laboratório em três passagens:

1. **Guiada:** leia, antecipe o resultado, execute, observe a API e os logs.
2. **Autônoma:** parta do enunciado, escreva os manifests e use consultas pontuais (`kubectl explain`, ajuda dos comandos e suas notas), sem copiar a solução.
3. **Operacional:** provoque a falha indicada, identifique a causa e recupere medindo tempo e impacto.

Consultar documentação faz parte da competência, mas não será uma pré-leitura escondida. As aulas ensinam o necessário para seus objetivos e deixam fontes de aprofundamento em **Referências opcionais**, depois do fechamento. Quando houver treino de consulta, o exercício informa a pergunta, o recorte e quando parar. Abrir um link não implica estudar toda a página nem seguir seus outros links.

Copiar um comando sem explicar o efeito não conta como conclusão. Ajuda de um tutor é útil na passagem guiada; nas avaliações, tente primeiro e peça uma pista, não a solução inteira. A autonomia aumenta por variações dos mecanismos já ensinados, não por omitir instruções necessárias. Se faltou uma explicação para cumprir um objetivo declarado, registre a lacuna do material; isso não é automaticamente falta de estudo sua.

## O começo e o fim de uma aula

Leia primeiro `Antes de começar` e `O que você vai conseguir fazer`. Esses trechos delimitam conhecimentos anteriores, ferramentas, ambiente e resultado. Pré-requisito significa uma etapa conhecida antes de iniciar, não uma descoberta no meio do capítulo. Os arquivos locais indicados nos procedimentos são parte da prática; não é necessário navegar pelo repositório inteiro.

Depois percorra explicações, exemplos e exercícios na ordem. Faça pausas nos checkpoints, mesmo que um capítulo ocupe vários dias. No `Fechamento`, confira a síntese e as perguntas: se você consegue explicar e demonstrar o resultado da rubrica, a aula terminou. Pode avançar sem abrir as referências opcionais.

Autossuficiência não significa cobrir toda uma especialidade. Cada capítulo explicita o que ainda fica para módulos posteriores ou aprofundamento. Regras atuais de contratação de exames e adaptação a versões fora da base do curso são verificações futuras, não requisitos de leitura para a primeira aula.

## Continuidade dos ambientes

O cluster-base começa em 1.35 no módulo 01. Sua primeira construção e destruição são manuais; depois disso, o Terraform de apoio pode recriar a infraestrutura e o primeiro CP entre sessões, enquanto join dos workers e restauração dos objetos continuam manuais. Preserve manifests, versões e evidências, não recursos cobrados ociosos. O módulo 08 prepara um auxiliar separado: nele você restaura etcd e ensaia 1.35 → 1.36. Reserve orçamento para essa janela adicional e descarte o auxiliar após salvar evidências e backups protegidos.

Os módulos 09/10 voltam ao cluster-base reconstruído; o EKS do módulo 11 é outro ambiente, com acesso isolado e limpeza própria. O módulo 12 usa a reconstrução corrente para o projeto. Cada aula indica o estado lógico que deve ser exportado ou reaplicado antes de destruir a infraestrutura física.

## Sequência

| Etapa | Estudo e prática | Evidência necessária |
|---|---|---|
| 00 | [Como estudar](curso/00-como-estudar.md) | Inventário inicial da aplicação, plano isolado do lab, agenda e teto de gasto |
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

**Marco 1 — Publicar e explicar (00–03).** Você consegue representar os requisitos de um serviço stateless com Deployment + Service, explicar quem recria um Pod e diagnosticar o caminho cliente → Traefik → Service → Pod. Além de reproduzir a base guiada, publique uma variação independente dela ou um componente de aplicação própria, com dados de laboratório. Compare o resultado com o inventário do módulo 00.

**Marco 2 — Operar (04–08).** Você distingue falha de aplicação, scheduler, CNI, CSI e control plane; recupera dados e faz manutenção com uma sequência verificada. Complete o simulado A depois do módulo 09, que fornece os exercícios de empacotamento usados na avaliação.

**Marco 3 — Projetar (09–12).** Você defende escolhas de disponibilidade, acesso, custo e operação. Complete o simulado B e o projeto final. Explique o que muda entre cluster manual e EKS, sem assumir que uma configuração de um funciona no outro.

## Aprovação de um módulo

A rubrica específica de cada capítulo é a referência. O módulo 00 termina com seu checklist de preparação, sem exigir instalação nem recuperação executada. Nos módulos práticos, entregue o laboratório, o desafio autônomo e evidência de recuperação para marcar a conclusão. Registre as ajudas recebidas. Se passou pelo roteiro mas não consegue repetir o desafio, marque **em prática**.

O projeto final usa rubrica de 100 pontos no módulo 12. A meta interna dos simulados é **80/100 em duas tentativas independentes**, sem falhas críticas de contexto, perda de dados ou permissões excessivas. Isso é um critério de treino do curso, não a nota oficial de uma prova nem garantia de contratação.

## O que fica para depois

Desenvolver um operator próprio, service mesh, eBPF profundo, múltiplos clusters e CKS completa são especializações posteriores. Você aprenderá a instalar e usar CRDs/operators e a diagnosticá-los, sem precisar escrever um controller para publicar a primeira aplicação. Rancher e Portainer podem entrar como exercício adicional depois do marco operacional.

Use [PROGRESSO.md](PROGRESSO.md) a cada sessão. Comece agora pelo [módulo 00](curso/00-como-estudar.md).
