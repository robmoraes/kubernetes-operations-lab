# 00 — Como estudar e demonstrar competência

Você já opera mais de 100 serviços em Swarm. O curso parte dessa experiência: o trabalho será transferir suas decisões de produção para a API, os controllers e as extensões do Kubernetes. Ao terminar, você deve conseguir construir, operar, recuperar e explicar uma plataforma, além de resolver tarefas práticas sob tempo. Concluir leituras ou instalar um chart não comprova, sozinho, essas capacidades.

**Carga de referência:** 240–320 horas, aproximadamente 14–18 semanas com 18–22 horas semanais. Os módulos são etapas, não semanas rígidas. Troubleshooting, restauração e projeto final merecem repetição; avance pela evidência de domínio, não pelo calendário.

## O resultado que você vai construir

O fio condutor é uma aplicação do seu Swarm. Comece com a aplicação mínima fornecida, aprenda o comportamento dos objetos e então migre um serviço real, com dados fictícios. O repositório deverá terminar com manifests, automação revisável, decisões de arquitetura, runbooks, incidentes investigados e um projeto final demonstrável.

O ambiente inicial tem um control plane e dois workers. O percurso acrescenta rede, armazenamento, segurança, manutenção, entrega, HA, EKS e práticas SRE. Prometheus e Loki aparecem quando houver uma pergunta operacional para responder; não são pré-requisitos para o primeiro control plane.

## Quais conhecimentos transferir do Swarm

| Experiência atual | Conhecimento a acrescentar | Cuidado com a analogia |
| --- | --- | --- |
| Service replicado | Deployment, ReplicaSet e Pod | Service no Kubernetes é descoberta/acesso de rede |
| Stack/Compose | Manifests, Helm e Kustomize | Não existe tradução perfeita, sobretudo para estado e rede |
| Manager e consenso | API Server, etcd e controllers | etcd usa Raft; não equivale a todo o control plane |
| Labels do Traefik | Ingress, Gateway e HTTPRoute | Precisa de controller para implementar as regras |
| Overlay | CNI e dataplane de Services | CNI não é necessariamente uma rede overlay |
| Constraints | Affinity, taints e topology spread | Distribuir réplicas é diferente de garantir quórum |
| Healthcheck | Startup, readiness e liveness | Falha de readiness retira tráfego, não reinicia container |
| Volumes | PV, PVC, StorageClass e CSI | Portabilidade depende do backend e de sua topologia |

Swarm também é declarativo e reconcilia estado desejado. A novidade aqui é a divisão dessa responsabilidade em APIs e controllers distintos, com mais pontos de integração e diagnóstico. Leia a [visão de componentes](https://kubernetes.io/docs/concepts/overview/components/) junto com a [explicação de controllers](https://kubernetes.io/docs/concepts/architecture/controller/).

## Uma sessão de estudo útil

1. **Recordar, 10 minutos:** explique o conceito anterior sem consultar notas.
2. **Formular uma hipótese, 10 minutos:** escreva o que espera que aconteça no laboratório.
3. **Executar, 60–90 minutos:** observe objetos, eventos, logs e o resultado para o cliente.
4. **Provocar uma falha, 20–40 minutos:** altere uma variável e registre sintoma, hipótese, teste e causa.
5. **Concluir, 15 minutos:** restaure, prove o resultado e escreva o que faria diferente em produção.

Durante a primeira execução, consulte o material livremente. Na segunda, abra somente a documentação oficial. Na terceira, use cronômetro e guarde a solução antes de olhar o gabarito. Uma resposta decorada perde valor quando o namespace, a porta ou o contexto muda.

Nos dias úteis, faça blocos curtos de teoria e tarefas de 20–40 minutos. Reserve os finais de semana para instalação, upgrades, restauração e exercícios de arquitetura. Deixe tempo para desprovisionar os recursos pagos depois de confirmar o que ainda será necessário.

## Onde cada comando roda

- **LOCAL:** seu computador com o clone deste repositório, acesso à rede privada do laboratório e, a partir do módulo 01, kubeconfig exclusivo do curso.
- **HOST CP:** sessão SSH no control plane; comandos com sudo alteram essa máquina.
- **HOST WORKER:** sessão SSH em um worker identificado pelo nome.
- **TODOS OS HOSTS:** repetir em CP e workers novos, nunca na máquina que hospeda seu Swarm de produção.

Os exemplos assumem Bash e comandos LOCAL executados na raiz do repositório. Confira contexto e namespace antes de cada exercício. As credenciais de administração do laboratório devem ficar fora do Git; evidências públicas precisam estar sem tokens, certificados privados, Secrets e dados de clientes.

```bash
# LOCAL — quando já existir um cluster
kubectl config current-context
kubectl config view --minify
kubectl get nodes -o wide
```

`config view` sem `--raw` oculta material sensível; mesmo assim, revise hosts e identidades antes de publicar a saída. Um contexto escolhe cluster, identidade e namespace. É possível ter vários contextos no mesmo arquivo, mas o curso começa com um kubeconfig separado para tornar o alvo inequívoco. [Organização de acesso](https://kubernetes.io/docs/concepts/configuration/organize-cluster-access-kubeconfig/).

## Como produzir evidências

Crie um registro por laboratório usando os templates do repositório. Cada registro deve conter objetivo, data, versões, contexto, hipótese, comandos relevantes, resultado observado, diagnóstico e recuperação. Saídas pequenas e comentadas são mais úteis que uma transcrição de 500 linhas.

Exemplo de uma conclusão verificável: “Às 15:08, o Service tinha dois endpoints prontos. Ao remover a label esperada do seletor, os endpoints ficaram vazios e o cliente falhou. Restaurar o seletor recuperou o HTTP 200; os containers nunca reiniciaram.” Isso diferencia falha de descoberta de falha de processo.

Para cada módulo, produza também uma resposta de entrevista de dois minutos: problema, mecanismo, tradeoff e validação. Você deve conseguir defender por que escolheu uma solução e explicar uma situação em que escolheria outra.

## Regra de avanço e rubrica comum

Cada item abaixo vale 0, 1 ou 2: não conseguiu; conseguiu consultando a solução; conseguiu com documentação e explicação própria.

| Dimensão | O que demonstra 2 pontos |
| --- | --- |
| Conceito | Explica mecanismo e limites sem depender de analogia |
| Execução | Reconstrói o resultado e seleciona contexto/namespace corretos |
| Diagnóstico | Isola a causa por evidências e evita mudanças aleatórias |
| Recuperação | Restaura o serviço e comprova comportamento do cliente |
| Comunicação | Entrega manifest/runbook e explica riscos e alternativas |

Avance com **8/10 ou mais**, sem zero em recuperação. Se falhar, repita apenas a dimensão fraca com uma variação do exercício. A meta de tempo só passa a contar depois da correção técnica.

## Falha de método e recuperação

O incidente de estudo mais comum é “rodei tudo, ficou verde, mas não sei repetir”. A recuperação é fechar o passo a passo, recriar o recurso em outro namespace e prever três resultados antes de executar: o controller responsável, o evento esperado e o teste do cliente. Compare previsão e realidade. Se só conseguir corrigir reinstalando, volte à árvore de diagnóstico do módulo.

Outra armadilha é adaptar a própria hipótese à saída. Preserve a previsão original no registro. Ao investigar profissionalmente, descartar uma hipótese com um teste pequeno já é progresso.

## Exercício autônomo de entrada

**Tempo: 45–60 minutos; sem cluster necessário.** Escolha um serviço stateless real do seu Swarm e escreva: imagem/arquitetura, portas, dependências, secrets, volumes, réplicas, probes atuais, estratégia de atualização, entradas Traefik, SLO e rollback. Separe os requisitos conhecidos das suposições.

Entregue uma proposta inicial de quais objetos Kubernetes seriam necessários. Ainda não precisa acertar todos os campos YAML. Reavalie a proposta ao terminar os módulos 03, 06 e 09: o histórico da sua decisão será parte do portfólio.

**Aprovação:** nenhum segredo no documento, dados persistentes identificados, uma validação de sucesso percebida pelo usuário e um rollback concreto. “O pod ficou Running” não basta para provar que a aplicação funciona.

## Trabalho e certificação

Use a trilha principal para administração e CKA; os módulos de aplicação e entrega também apoiam CKAD, e segurança abre caminho para CKS. Não trate aprovação em prova como sinônimo de prontidão para qualquer produção. Trate o projeto final, os incidentes e os simulados como evidências complementares.

Regras, versões do ambiente e conteúdo dos exames mudam. Antes de agendar, confira os [currículos públicos da CNCF](https://github.com/cncf/curriculum) e o [manual oficial do candidato](https://docs.linuxfoundation.org/tc-docs/certification/lf-handbook2). A matriz e os simulados deste repositório devem ser revistos contra essas fontes; não use questões vazadas.

Fontes oficiais consultadas em **10/09/2026**. Próximo passo: [01 — Construir e compreender o control plane](01-control-plane.md).
