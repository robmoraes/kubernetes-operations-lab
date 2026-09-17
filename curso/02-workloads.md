# 02 — Workloads, configuração e reconciliação

Um container funcionando é apenas parte da operação de uma aplicação. Nesta aula você declarará réplicas, configuração e condições de prontidão, acompanhará uma atualização e recuperará duas falhas. O objetivo é entender quem reage à mudança e o que realmente foi restaurado.

## Antes de começar

**Duração:** 16–20 horas. Conclua o módulo 01: cluster com workers Ready, Calico/CoreDNS saudáveis e teste de rede aprovado. Use a estação Linux com kubectl instalado, PATH e KUBECONFIG do curso exportados. Todos os comandos são **LOCAL**, na raiz do repositório, contexto `curso-kubeadm`.

Os manifests de [laboratorios/02-workloads](../laboratorios/02-workloads/) são o material desta aula, não uma leitura complementar. Você aprenderá a lê-los antes de aplicar. A aplicação usa dados fictícios, não requer PVC nem um serviço externo. O namespace `curso` será mantido para os próximos módulos.

## O que você vai conseguir fazer

- Explicar como Deployment, ReplicaSet, Pod e Service cooperam.
- Publicar duas réplicas HTTP com configuração, recursos e probes justificados.
- Observar substituição, escala e atualização; recuperar falhas de readiness e imagem.
- Executar um Job, controlar um CronJob e observar um DaemonSet por nó elegível.
- Delimitar o que um rollback de Deployment restaura e o que permanece fora dele.

## Como os recursos dividem as responsabilidades

No Kubernetes, manter uma aplicação em execução e fornecer um endereço para acessá-la são responsabilidades de recursos diferentes. O **Deployment** declara a execução e a estratégia de atualização; seu **ReplicaSet** mantém a quantidade de Pods; o **Service** seleciona backends e oferece um endereço estável. O Pod é a unidade agendada: containers do mesmo Pod compartilham IP e podem compartilhar volumes. Containers de Pods distintos não compartilham localhost.

Apagar um Pod de um Deployment não reduz o número desejado de réplicas: o controller cria outro. Um Pod isolado, sem controller proprietário, não recebe essa substituição automática. O substituto tem outra identidade e pode ter outro IP/nó. `ownerReferences` registra qual objeto é proprietário daquele recurso; no laboratório seguiremos Pod → ReplicaSet → Deployment.

## 1. Ler o manifesto antes de aplicar

Abra os arquivos de [laboratorios/02-workloads](../laboratorios/02-workloads/). A base usa BusyBox com `httpd`, porta 8080, usuário 1000, filesystem raiz somente leitura e conteúdo montado de ConfigMap. O Service usa **80 → porta nomeada http → 8080**. Não há PVC: perder o container não perde informação exclusiva porque o conteúdo está declarado na ConfigMap.

Um **manifest** é a descrição YAML de um objeto. `apiVersion` escolhe a versão da API; `kind`, o tipo; `metadata`, nome/namespace/labels; `spec`, o estado desejado. O `---` separa objetos quando há vários no mesmo arquivo. Indentação delimita campos; um campo dentro do template do Pod não configura o Deployment inteiro.

Leia os cinco arquivos nesta ordem e encontre apenas o papel indicado:

| Arquivo | O que localizar | Relação com a aplicação |
| --- | --- | --- |
| `namespace.yaml` | `metadata.name: curso` | Agrupa os recursos da aula |
| `configmap.yaml` | `data` com HTML, healthz e readyz | Fornece arquivos não secretos ao servidor |
| `deployment.yaml` | `replicas`, `selector` e `template` | Declara quantos Pods manter e como criá-los |
| `service.yaml` | `selector`, `port` e `targetPort` | Seleciona Pods com `app: web` e encaminha 80 para 8080 |
| `kustomization.yaml` | Lista `resources` | Reúne os quatro objetos anteriores para aplicar em conjunto |

**Labels** são pares chave/valor usados para classificar objetos; **selectors** escolhem objetos cujas labels combinam. Neste exemplo, o selector do Deployment deve combinar com as labels de seu template. O Service usa essas mesmas labels, mas não é proprietário dos Pods. `containerPort: 8080` informa uma porta; não faz o processo escutar sozinho — isso é definido pelos argumentos do `httpd`.

O **Pod template**, em `spec.template`, é o molde de novos Pods. Alterar esse molde inicia uma nova revisão do Deployment; alterar só `replicas` muda a quantidade sem criar uma nova versão do molde. `RollingUpdate` troca réplicas gradualmente. Nosso `maxUnavailable: 0` preserva as duas réplicas disponíveis durante a troca e `maxSurge: 1` permite um Pod extra, se houver capacidade. `minReadySeconds: 5` exige estabilidade de prontidão antes de considerar a nova réplica disponível.

`requests` informa a necessidade usada pelo scheduler ao reservar capacidade; `limits` estabelece limites de execução, não a reserva. CPU pode sofrer throttling; excesso de memória pode levar a OOMKill. Requests/limits também influenciam a classe de qualidade de serviço: neste exemplo, são diferentes e o Pod é Burstable. `50m` equivale a 0,05 CPU; `32Mi` é memória binária. O módulo 05 aprofundará a disputa por recursos. Não dimensione uma aplicação real copiando esses números: são valores para um servidor didático mínimo.

**Consulta técnica delimitada, 5 minutos:** os dois comandos `explain` abaixo consultam a referência da API do cluster. Use-os para confirmar o significado de `strategy` e localizar o campo `httpGet` da readiness. Encerre a consulta quando identificar os dois; não é preciso ler toda a árvore. A explicação necessária está nesta aula.

```bash
kubectl config current-context
kubectl explain deployment.spec.strategy
kubectl explain pod.spec.containers.readinessProbe
kubectl kustomize laboratorios/02-workloads/
kubectl apply -k laboratorios/02-workloads/
kubectl rollout status deployment/web -n curso --timeout=180s
kubectl get deployment,replicaset,pod,service -n curso -o wide
kubectl get endpointslice -n curso -l kubernetes.io/service-name=web
```

O uso de `-k` processa a Kustomization; nesta base ela apenas reúne os arquivos listados. Kustomize também permite compor variações, assunto do módulo 09. Namespace faz parte dos manifests, então não é preciso mudar o namespace padrão do contexto. Não use `kubectl apply -f` recursivo sobre todos os laboratórios: vários arquivos são falhas ou exercícios alternativos.

**Evidência:** Deployment disponível com duas réplicas, Pods prontos, Service ClusterIP e EndpointSlice com dois endereços prontos. Se apenas um worker tiver capacidade, as duas réplicas podem ficar nele; quantidade de réplicas não garante distribuição física.

```bash
kubectl port-forward -n curso svc/web 8080:80
# Outro terminal LOCAL, mantendo o anterior aberto
curl -fsS http://127.0.0.1:8080/
curl -fsS http://127.0.0.1:8080/healthz
```

`port-forward` chega a um backend pela API/kubelet e não prova o balanceamento pelo ClusterIP. O módulo 03 fará a verificação pelo dataplane. Anote o método de acesso ao registrar um teste; “HTTP funcionou” sem dizer por qual caminho pode esconder a falha investigada.

Os curls devem retornar o HTML da ConfigMap e a resposta de healthz. Encerre esse túnel com Ctrl+C após o teste. Ao substituir o Pod usado pelo túnel nas próximas etapas, o processo pode terminar; inicie um novo `port-forward` quando precisar testar de novo. Isso é diferente de o Service perder seu endereço interno.

## 2. Observar substituição e escala

```bash
kubectl get pods -n curso -l app=web -o custom-columns=NAME:.metadata.name,UID:.metadata.uid,IP:.status.podIP,NODE:.spec.nodeName
POD=$(kubectl get pods -n curso -l app=web -o jsonpath='{.items[0].metadata.name}')
kubectl get pod "$POD" -n curso -o jsonpath='{.metadata.ownerReferences}'
kubectl delete pod "$POD" -n curso
kubectl rollout status deployment/web -n curso --timeout=180s
kubectl get pods -n curso -l app=web -o wide
kubectl scale deployment/web -n curso --replicas=3
kubectl get deployment/web -n curso
```

O Deployment não foi reiniciado: um Pod foi substituído. Compare UID, idade e IP. O Service mantém seu endereço e atualiza os backends por labels/readiness. Volte à configuração declarada com `kubectl apply -k laboratorios/02-workloads/` e explique por que a escala retorna para duas réplicas. No GitOps, mudanças imperativas podem ser revertidas por outro controller; precisamos saber quem é dono de cada decisão.

## 3. ConfigMap e Secret

Uma **ConfigMap** armazena pares de configuração não secreta. No exemplo, cada chave vira um nome de arquivo e seu valor vira o conteúdo: `web-conteudo` é projetada em `/www`. Edite o texto de `index.html` no arquivo ConfigMap, aplique a base e aguarde a projeção chegar aos pods. A atualização do volume não é instantânea. Nosso servidor lê o arquivo por requisição; aplicações que só leem configuração ao iniciar precisam de reload/restart. ConfigMap em variável de ambiente não atualiza um processo já iniciado, e montagem de uma chave com `subPath` não recebe as atualizações automáticas do volume.

```bash
kubectl get configmap/web-conteudo -n curso -o yaml
kubectl exec -n curso deployment/web -- cat /www/index.html
kubectl rollout restart deployment/web -n curso
kubectl rollout status deployment/web -n curso --timeout=180s
```

O restart acima é um exercício para observar substituição; não é necessário para esse servidor ler o HTML atualizado após a projeção. Um rollout de Deployment não versiona automaticamente o conteúdo de uma ConfigMap externa: `rollout undo` não restaura todas as dependências. Volte ao conteúdo anterior no arquivo quando terminar e reaplique.

Um **Secret** é o objeto destinado a dados sensíveis, como uma credencial. `data` em base64 não é criptografia; o objeto ainda exige acesso restrito e proteção do armazenamento. Aqui basta distinguir as finalidades; criação e controle de acesso serão praticados no módulo 06. Não coloque credenciais reais dentro desta ConfigMap nem em manifests versionados.

## 4. Separar os três tipos de probe

| Probe | Pergunta operacional | Efeito da falha persistente |
| --- | --- | --- |
| Startup | O processo terminou sua inicialização? | Reinicia container; enquanto não passa, adia as outras probes |
| Readiness | Este backend pode receber tráfego agora? | Marca Pod como não pronto e retira dos endpoints prontos |
| Liveness | O processo precisa ser reiniciado para se recuperar? | Kubelet reinicia o container |

Use liveness com parcimônia: se depender do banco remoto, uma falha do banco pode reiniciar toda a frota sem resolver a causa. Startup é útil para início lento; aumentar liveness indiscriminadamente mistura início e operação normal. Neste laboratório `/healthz` e `/readyz` têm respostas estáticas; numa aplicação real, precisam representar condições úteis.

Leia os campos das probes no Deployment: `httpGet` define caminho/porta; `periodSeconds`, o intervalo; `failureThreshold`, quantas falhas consecutivas tornam a checagem falha. A startup do exemplo admite aproximadamente 60 segundos de tentativas (30 × 2), sem tratar isso como relógio exato. Readiness não reinicia o container: o processo pode continuar Running enquanto o Pod deixa de ser um backend pronto. Os EndpointSlices são os registros dos backends de um Service e de suas condições.

**Falha guiada — quebrar somente a readiness da nova versão:**

```bash
kubectl patch deployment web -n curso --type=json -p='[{"op":"replace","path":"/spec/template/spec/containers/0/readinessProbe/httpGet/path","value":"/rota-inexistente"}]'
kubectl rollout status deployment/web -n curso --timeout=45s
kubectl get pods -n curso -l app=web
kubectl describe pods -n curso -l app=web
kubectl get endpointslice -n curso -l kubernetes.io/service-name=web -o yaml
```

O timeout do rollout é esperado. O novo Pod está Running, mas não Ready; os antigos continuam servindo porque `maxUnavailable: 0` e `maxSurge: 1`. Readiness falhando não deve aumentar seu contador de restarts. Falta de capacidade para o Pod extra também pode travar esse rollout; procure o evento antes de atribuir tudo à probe.

**Recuperação:** `kubectl rollout undo deployment/web -n curso`, seguido de `kubectl rollout status deployment/web -n curso --timeout=180s`. Verifique de novo `/healthz` e endpoints. O comando undo corrige o Pod template para a revisão anterior; confira se ela é realmente a revisão saudável com `kubectl rollout history deployment/web -n curso`.

## 5. Atualização defeituosa e limite do rollback

```bash
kubectl set image deployment/web -n curso web=busybox:tag-inexistente-curso
kubectl get pods -n curso -l app=web
kubectl get events -n curso --sort-by=.lastTimestamp
kubectl rollout history deployment/web -n curso
kubectl rollout undo deployment/web -n curso
kubectl rollout status deployment/web -n curso --timeout=180s
kubectl apply -k laboratorios/02-workloads/
```

Espere `ErrImagePull` e depois `ImagePullBackOff` no novo Pod antes de executar o undo. O Deployment sinaliza falta de progresso, mas não executa rollback automático ao atingir `progressDeadlineSeconds`. O operador humano ou outra automação decide a recuperação. Diferencie um rollback do Pod template de rollback de banco de dados: migrações destrutivas não são desfeitas por esse comando.

Registre o digest executado, além da tag: `kubectl get pods -n curso -l app=web -o jsonpath='{range .items[*]}{.metadata.name}{" "}{.status.containerStatuses[0].imageID}{"\n"}{end}'`. A tag é um nome que pode apontar a outro conteúdo no futuro; o digest identifica conteúdo. A imagem `busybox:1.37.0` tem variantes ARM64/AMD64. Um digest da variante ARM64 é diferente do digest do índice multiarch, que referencia as variantes.

## 6. Tarefas finitas e agentes por nó

Deployment é apropriado para execução contínua. Um **Job** acompanha uma tarefa até a conclusão: o processo termina com código zero no sucesso e código diferente de zero na falha. Abra [extras/batch.yaml](../laboratorios/02-workloads/extras/batch.yaml). O Job executa um `wget` no Service `web`; dentro do namespace `curso`, esse nome é resolvido pelo DNS interno. É um teste de cliente pela rede do cluster, complementar ao `port-forward`.

`restartPolicy: Never` faz o container que terminou não ser reiniciado naquele Pod; o controller do Job ainda pode criar outra tentativa. `backoffLimit: 2` limita retries, e `activeDeadlineSeconds: 90` limita a duração ativa do Job. `Complete` significa que o trabalho terminou com sucesso, não que deve ficar rodando para sempre. Compare a saída do log com o código de conclusão do Pod.

Um **CronJob** cria Jobs conforme um calendário. No mesmo arquivo, `schedule: '*/5 * * * *'` significa a cada cinco minutos; `timeZone: Etc/UTC` torna o fuso explícito. `suspend: true` impede novos agendamentos, sem cancelar Jobs que já começaram. `concurrencyPolicy: Forbid` evita sobreposição de Jobs desse mesmo CronJob; não é uma trava global. O histórico retém um Job bem-sucedido e um com falha.

CronJob não garante execução de negócio exatamente uma vez. Uma tarefa **idempotente** pode ser repetida sem duplicar seu efeito: consultar uma página é um exemplo; cobrar novamente um cliente, não. Essa propriedade deve estar na aplicação, não ser presumida a partir do calendário.

```bash
kubectl apply -f laboratorios/02-workloads/extras/batch.yaml
kubectl wait -n curso --for=condition=Complete job/verificar-web --timeout=120s
kubectl logs -n curso job/verificar-web
kubectl create job verificar-manual -n curso --from=cronjob/verificar-web-periodico
kubectl wait -n curso --for=condition=Complete job/verificar-manual --timeout=120s
kubectl logs -n curso job/verificar-manual
```

O CronJob fornecido começa suspenso; criar um Job manual a partir dele valida o template sem esperar o calendário. Para observar o scheduler de CronJobs, mude temporariamente para uma execução por minuto e aceite apenas horários atrasados em até 30 segundos (`startingDeadlineSeconds`). Isso evita tentar recuperar uma longa sequência de horários perdidos ao dessuspender.

```bash
kubectl patch cronjob verificar-web-periodico -n curso --type=merge -p='{"spec":{"schedule":"* * * * *","startingDeadlineSeconds":30,"suspend":false}}'
kubectl get jobs -n curso -w
# Ao aparecer um Job verificar-web-periodico-..., encerre a observação com Ctrl+C.
# Pare em até dois minutos e suspenda mesmo se nenhum Job aparecer.
kubectl patch cronjob verificar-web-periodico -n curso --type=merge -p='{"spec":{"suspend":true}}'
kubectl get cronjob verificar-web-periodico -n curso
kubectl get jobs,pods -n curso
```

Registre o nome do Job criado pelo calendário e examine-o com `kubectl describe job NOME_REAL -n curso` e `kubectl logs job/NOME_REAL -n curso`. Se não houver criação, examine os eventos do CronJob e o horário informado; não o deixe ativo esperando indefinidamente. Ao concluir, remova os dois recursos declarados de batch com `kubectl delete -f laboratorios/02-workloads/extras/batch.yaml` e o Job manual com `kubectl delete job verificar-manual -n curso`. A exclusão do CronJob também remove seus Jobs dependentes; preserve o namespace `curso`.

### Um agente por nó, com DaemonSet

Um **DaemonSet** mantém um Pod por nó elegível, acompanhando entrada e saída de nós. Não tem `replicas` para você igualar manualmente à quantidade de máquinas. Agentes de rede e coleta costumam precisar desse vínculo com o nó; nossa demonstração apenas imprime informações e aguarda, sem acesso privilegiado ao host.

Abra [extras/daemonset.yaml](../laboratorios/02-workloads/extras/daemonset.yaml). O selector combina com as labels do template, como no Deployment. `nodeSelector` limita a Linux. Não há toleration para o taint do CP, portanto o cluster inicial deve ter dois Pods, um por worker. `NODE_NAME` usa `fieldRef: spec.nodeName` para receber informação do próprio Pod; esse mecanismo chama-se Downward API. Já `hostname` dentro do container mostra o hostname do Pod, não necessariamente o do host físico.

```bash
kubectl apply -f laboratorios/02-workloads/extras/daemonset.yaml
kubectl rollout status daemonset/agente-aula -n curso --timeout=180s
kubectl get daemonset agente-aula -n curso
kubectl get pods -n curso -l app=agente-aula -o wide
kubectl logs -n curso -l app=agente-aula --prefix
kubectl delete -f laboratorios/02-workloads/extras/daemonset.yaml
```

Compare `DESIRED`, `CURRENT` e `READY` com o número de workers elegíveis. Se houver um terceiro worker ingressado no módulo 01, espere três, não dois. Todos os Pods ficam sem privilégios e sem `hostPath`. O módulo 05 explicará como taints, tolerations e seletores determinam elegibilidade; aqui basta observar a regra já declarada no exemplo.

## Exercício autônomo e rubrica

**Tempo: 90 minutos.** Em namespace `desafio-workloads`, implemente um serviço de sua escolha, compatível com a arquitetura: duas réplicas, ConfigMap, Service, requests/limits e as três probes. Você pode usar a imagem BusyBox já fornecida para criar outro servidor HTTP com conteúdo próprio; não precisa possuir uma aplicação ou imagem publicada. Prove atualização sem enviar tráfego ao backend não pronto. Crie um Job que confirme a resposta. Entregue YAML, evidência do cliente e um rollback reproduzível.

**Variação de DaemonSet, 30 minutos:** no namespace do desafio, escreva um agente que imprime o nome do Pod e do nó e aguarda. Use imagem fixa, recursos baixos, sem toleration do CP e nenhum hostPath privilegiado. Antes de aplicar, preveja quantos Pods aparecerão e justifique. Confira sua previsão e remova somente o DaemonSet ao terminar.

**Rubrica, 10 pontos:** 2 para distinguir Pod/ReplicaSet/Deployment/Service; 2 para probes e recursos justificados; 2 para atualização e rollback; 2 para Job e teste de cliente; 2 para reconstrução sem copiar a solução. Exija 8/10 e aplicação restaurada. Pergunta de entrevista: “Por que Running não significa pronto para tráfego e por que rollback de Deployment não garante rollback da aplicação inteira?”

## Fechamento

Você declarou uma aplicação e observou que diferentes controllers respondem por diferentes resultados. Deployment mantém execução contínua e revisões de Pod template; Job acompanha conclusão; CronJob cria Jobs pelo calendário; DaemonSet acompanha nós elegíveis. Service não executa containers: seleciona os backends que atendem ao tráfego.

Antes de avançar, explique: por que apagar um Pod não reduz réplicas? Qual probe deve retirar tráfego sem reiniciar? Por que a ConfigMap não volta automaticamente no undo? Qual evidência distingue um Job concluído de um container que deve continuar rodando? As respostas devem se apoiar nos testes que você executou.

Conclua com 8/10 na rubrica, os dois incidentes recuperados e a aplicação-base saudável. Preserve `curso/web`, seu Service e a ConfigMap; remova os recursos temporários de batch/DaemonSet como orientado. Se apagar o namespace independente do desafio, salve antes as evidências e confirme que ele não contém nada além do seu exercício. Não foi ensinado ainda dimensionamento de produção, armazenamento persistente ou publicação externa. Próximo: [03 — Rede, Traefik, Ingress e Gateway API](03-rede.md).

## Referências opcionais

Nenhuma leitura externa é necessária para cumprir esta aula. Base de fontes consultada em 10/09/2026; comportamento de CronJob e DaemonSet reconferido em 12/09/2026.

- [Deployments](https://kubernetes.io/docs/concepts/workloads/controllers/deployment/) — outras estratégias, condições e detalhes do histórico de revisões.
- [Ciclo de vida de Pods](https://kubernetes.io/docs/concepts/workloads/pods/pod-lifecycle/) — condições e transições além das observadas nos dois incidentes.
- [Recursos de containers](https://kubernetes.io/docs/concepts/configuration/manage-resources-containers/) — opções de gerenciamento de recursos que serão aprofundadas no módulo 05.
- [ConfigMaps](https://kubernetes.io/docs/concepts/configuration/configmap/) e [Secrets](https://kubernetes.io/docs/concepts/configuration/secret/) — outros modos de projeção e suas limitações.
- [Probes](https://kubernetes.io/docs/tasks/configure-pod-container/configure-liveness-readiness-startup-probes/) — exemplos TCP, exec e gRPC além do HTTP usado aqui.
- [Jobs](https://kubernetes.io/docs/concepts/workloads/controllers/job/) — paralelismo e tratamento de falhas mais elaborado.
- [CronJobs](https://kubernetes.io/docs/concepts/workloads/controllers/cron-jobs/) — particularidades de horários perdidos, concorrência e calendário.
- [DaemonSets](https://kubernetes.io/docs/concepts/workloads/controllers/daemonset/) — políticas de atualização e interação detalhada com o agendamento.
- [Catálogo oficial BusyBox](https://github.com/docker-library/official-images/blob/master/library/busybox) — publicação de tags e arquiteturas para quem quiser inspecionar a imagem usada.
