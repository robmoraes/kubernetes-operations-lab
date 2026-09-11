# Simulado A — recursos e diagnóstico

Tempo: **120 minutos**. Pontuação: **100**. Meta do curso: 80. Contexto: laboratório kubeadm dos módulos 01–09. Requisitos: 2 workers Ready, CNI com NetworkPolicy, kubectl e Kustomize. O PVC pode ser estático local: cloud não é pré-requisito desta prova.

## Preparação fora do relógio

Confirme que `prova-a` ainda não existe. Um namespace de tentativa anterior deve ser arquivado/limpo conscientemente; reaplicar o baseline sobre uma tentativa corrigida não recria o mesmo exame.

```bash
kubectl config current-context
kubectl get nodes
kubectl get namespace prova-a
# NotFound é esperado na primeira tentativa.
kubectl apply -f avaliacoes/fixtures/a-inicial.yaml
kubectl -n prova-a get pods,deploy,svc
```

Há três aplicações com problemas intencionais. Não é esperado que todas estejam prontas. Use o namespace `prova-a` em todas as tarefas, salvo a CRD, que tem escopo de cluster. Anote diagnóstico **antes** de mudar os objetos.

## Tarefas

| Item | Pontos | Estado final exigido |
|---|---|---|
| 1 — RBAC | 10 | ServiceAccount `auditor`, Role e RoleBinding: pode get/list/watch Pods somente em prova-a; não pode listar Secrets nem Pods em default |
| 2 — Kustomize | 10 | Base e overlay `teste` próprios geram Deployment `relatorio` com imagem busybox:1.37.0, uma réplica e label ambiente:teste; container executa sleep 3600; recursos declarados; manifeste renderizado e Pod Ready |
| 3 — extensão de API | 5 | CRD `relatorios.curso.example.com`, scope Namespaced, kind Relatorio, versão v1; spec.destino string obrigatória. Criar objeto diario válido e demonstrar rejeição de spec.destino numérica sem alterar schema |
| 4 — configuração/probes | 10 | Deployment `pagina`, duas réplicas HTTP em 8080, imagem busybox:1.37.0, conteúdo via ConfigMap, readiness/startup válidas, request 100m/32Mi e limit 200m/64Mi; mudar conteúdo e comprovar atualização |
| 5 — Job | 5 | Job `contagem` busybox:1.37.0 termina exit 0 imprimindo valores 1–5; completions 1/backoffLimit 1, log salvo sem criar Deployment para esse trabalho |
| 6 — Service | 5 | Service `pagina` ClusterIP porta 80→8080, EndpointSlices prontos e respostaHTTP dentro do cluster |
| 7 — DNS | 5 | Registrar busca DNS de pagina.prova-a.svc.cluster.local e kubernetes.default.svc.cluster.local a partir de um Pod temporário; explicar namespaces e ClusterIP |
| 8 — NetworkPolicy | 10 | Ingress em Pods app:pagina permitido apenas a Pods com acesso:permitido no mesmo namespace emTCP8080; teste positivo e negativo. Não restringir os outros workloads |
| 9 — PV/PVC | 10 | PVC `dados`, 1Gi RWO, montado em `/dados` por Pod `gravador`; escrever marcador, recriar somente Pod e ler o mesmo marcador. Explicar zona/nodeAffinity e destino dos dados se PVC for excluído |
| 10 — incidente de rede | 10 | Recuperar HTTP do Service `api` já existente, preservando os nomes e a aplicação; documentar causa e evidência |
| 11 — incidente Pending | 10 | Recuperar `fila` sem remover taints do control plane nem alterar o cluster todo; documentar condição que bloqueava o scheduler |
| 12 — incidente readiness | 10 | Recuperar `saude` corrigindo a probe; preservar processo e readiness HTTP. Não vale remover a probe |

Os itens 1–3 exercitam arquitetura/configuração (25 p), 4–5 workloads (15 p), 6–8 rede (20 p), 9 storage (10 p), 10–12 troubleshooting (30 p). Dentro do item, divida igualmente a pontuação entre os critérios separados por ponto e vírgula; arredonde a nota final uma vez.

Para os itens novos, escreva YAML em arquivos próprios. Você pode usar comandos imperativos para gerar um rascunho, depois revisar. Para NetworkPolicy, clientes podem ser Pods busybox de longa duração criados por você com labels diferentes; use timeout e mostre que DNS/HTTP funcionavam antes do bloqueio.

Para storage estático, prepare o diretório em **um worker identificado**, defina `local`/nodeAffinity e StorageClass sem provisionador, com Retain. Não use `hostPath` como prova de portabilidade entre nós. Se escolher EBS, registre a AZ e prepare CSI/credenciais antes do relógio. A prova não pede exclusão do PVC.

## Entrega

Salve manifests, diagnóstico de cada incidente, comandos de verificação e tempo por tarefa. Não altere o baseline para esconder o defeito original. Faça a correção em sua tentativa e guarde o patch/explicação.

Depois do relógio, confira o [gabarito e critérios](gabaritos/simulado-a.md). A limpeza de namespace apagará os workloads e PVCs: confira primeiro os dados/volumes. Remova a CRD `relatorios.curso.example.com` apenas após confirmar que é a criada por este simulado e não tem objetos que você quer preservar.
