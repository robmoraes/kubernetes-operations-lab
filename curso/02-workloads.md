# 02 — Workloads, configuração e reconciliação

**Duração:** 14–18 horas. **Pré-requisitos:** módulo 01, cluster com workers Ready, LOCAL com kubectl e este repositório. **Entrega:** aplicação HTTP com duas réplicas, probes, limites, atualização e rollback demonstrados. Os comandos deste capítulo são **LOCAL**, na raiz do repositório, contexto `curso-kubeadm`.

## A divisão que muda sua operação

No Swarm, um Service reúne várias decisões de execução e publicação. No Kubernetes, o **Deployment** declara a execução e a estratégia de atualização; seu **ReplicaSet** mantém a quantidade de Pods; o **Service** seleciona backends e oferece um endereço estável. O Pod é a unidade agendada: containers do mesmo Pod compartilham IP e podem compartilhar volumes. Containers de Pods distintos não compartilham localhost.

Apagar um Pod de um Deployment não reduz o número desejado de réplicas: o controller cria outro. Um Pod isolado, sem controller proprietário, não recebe essa substituição automática. O substituto tem outra identidade e pode ter outro IP/nó. Inspecione `ownerReferences` para saber qual recurso reconciliará sua mudança. [Deployments](https://kubernetes.io/docs/concepts/workloads/controllers/deployment/) e [ciclo de vida de Pods](https://kubernetes.io/docs/concepts/workloads/pods/pod-lifecycle/).

## 1. Ler o manifesto antes de aplicar

Abra os arquivos de [laboratorios/02-workloads](../laboratorios/02-workloads/). A base usa BusyBox com `httpd`, porta 8080, usuário 1000, filesystem raiz somente leitura e conteúdo montado de ConfigMap. O Service usa **80 → porta nomeada http → 8080**. Não há PVC: perder o container não perde informação exclusiva porque o conteúdo está declarado na ConfigMap.

`requests` influencia a decisão do scheduler; `limits` controla o teto de uso do container. CPU pode sofrer throttling; excesso de memória pode levar a OOMKill. Neste exemplo, requests e limits diferem e o Pod é Burstable. `50m` equivale a 0,05 CPU; `32Mi` é memória binária. Não dimensione uma aplicação real copiando esses números: são valores para um servidor didático mínimo. [Recursos de containers](https://kubernetes.io/docs/concepts/configuration/manage-resources-containers/).

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

O uso de `-k` só reúne os arquivos listados pela Kustomization; a templating será estudada no módulo 09. Namespace faz parte dos manifests, então não é preciso mudar o namespace padrão do seu contexto. Não use `kubectl apply -f` recursivo sobre todos os laboratórios: vários arquivos são falhas ou exercícios alternativos.

**Evidência:** Deployment disponível com duas réplicas, Pods prontos, Service ClusterIP e EndpointSlice com dois endereços prontos. Se apenas um worker tiver capacidade, as duas réplicas podem ficar nele; quantidade de réplicas não garante distribuição física.

```bash
kubectl port-forward -n curso svc/web 8080:80
# Outro terminal LOCAL, mantendo o anterior aberto
curl -fsS http://127.0.0.1:8080/
curl -fsS http://127.0.0.1:8080/healthz
```

`port-forward` chega a um backend pela API/kubelet e não prova o balanceamento pelo ClusterIP. O módulo 03 fará a verificação pelo dataplane. Anote o método de acesso ao registrar um teste; “HTTP funcionou” sem dizer por qual caminho pode esconder a falha investigada.

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

`web-conteudo` é projetada como arquivos em `/www`. Edite o texto de `index.html` no arquivo ConfigMap, aplique a base e aguarde a projeção chegar aos pods. A atualização do volume não é instantânea. Nosso servidor lê o arquivo por requisição; aplicações que só leem configuração ao iniciar precisam de reload/restart. ConfigMap em variável de ambiente não atualiza um processo já iniciado, e montagem com `subPath` não recebe as atualizações automáticas do volume. [ConfigMaps](https://kubernetes.io/docs/concepts/configuration/configmap/).

```bash
kubectl get configmap/web-conteudo -n curso -o yaml
kubectl exec -n curso deployment/web -- cat /www/index.html
kubectl rollout restart deployment/web -n curso
kubectl rollout status deployment/web -n curso --timeout=180s
```

O restart acima é um exercício para observar substituição; não é necessário para esse servidor ler o HTML atualizado após a projeção. Um rollout de Deployment não versiona automaticamente o conteúdo de uma ConfigMap externa: `rollout undo` não restaura todas as dependências. Volte ao conteúdo anterior no arquivo quando terminar e reaplique.

Secrets têm semântica e controles próprios para dados sensíveis. `data` em base64 não é criptografia; um Secret ainda exige acesso restrito e proteção do armazenamento. No módulo 06 você tratará RBAC e gestão de segredos. Não coloque credenciais reais dentro desta ConfigMap nem em manifests versionados. [Secrets](https://kubernetes.io/docs/concepts/configuration/secret/).

## 4. Separar os três tipos de probe

| Probe | Pergunta operacional | Efeito da falha persistente |
| --- | --- | --- |
| Startup | O processo terminou sua inicialização? | Reinicia container; enquanto não passa, adia as outras probes |
| Readiness | Este backend pode receber tráfego agora? | Marca Pod como não pronto e retira dos endpoints prontos |
| Liveness | O processo precisa ser reiniciado para se recuperar? | Kubelet reinicia o container |

Use liveness com parcimônia: se depender do banco remoto, uma falha do banco pode reiniciar toda a frota sem resolver a causa. Startup é útil para início lento; aumentar liveness indiscriminadamente mistura início e operação normal. Neste laboratório `/healthz` e `/readyz` têm respostas estáticas; numa aplicação real, precisam representar condições úteis. [Probes](https://kubernetes.io/docs/tasks/configure-pod-container/configure-liveness-readiness-startup-probes/).

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

Espere `ErrImagePull` e depois `ImagePullBackOff` no novo Pod. O Deployment sinaliza falta de progresso, mas não executa rollback automático ao atingir `progressDeadlineSeconds`. O operador humano ou outra automação decide a recuperação. Diferencie um rollback do Pod template de rollback de banco de dados: migrações destrutivas não são desfeitas por esse comando. [Estado e progresso do Deployment](https://kubernetes.io/docs/concepts/workloads/controllers/deployment/#failed-deployment).

Registre o digest executado, além da tag: `kubectl get pods -n curso -l app=web -o jsonpath='{range .items[*]}{.metadata.name}{" "}{.status.containerStatuses[0].imageID}{"\n"}{end}'`. A imagem `busybox:1.37.0` publica ARM64/AMD64 no [catálogo Docker oficial](https://github.com/docker-library/official-images/blob/master/library/busybox). Um digest de imagem específico de ARM64 é diferente do digest do índice multiarch.

## 6. Tarefas finitas e agentes por nó

Deployment é apropriado para execução contínua. **Job** acompanha uma tarefa até completar, com política de retry. **CronJob** cria Jobs em um calendário; ele não garante que seu código de negócio execute exatamente uma vez. Faça tarefas idempotentes e use `concurrencyPolicy` quando sobreposição for indesejável. **DaemonSet** mantém um Pod nos nós elegíveis, útil para agentes; não é “um Deployment com réplicas iguais ao número de nós”. [Jobs](https://kubernetes.io/docs/concepts/workloads/controllers/job/), [CronJobs](https://kubernetes.io/docs/concepts/workloads/controllers/cron-jobs/) e [DaemonSets](https://kubernetes.io/docs/concepts/workloads/controllers/daemonset/).

```bash
kubectl apply -f laboratorios/02-workloads/extras/batch.yaml
kubectl wait -n curso --for=condition=Complete job/verificar-web --timeout=120s
kubectl logs -n curso job/verificar-web
kubectl create job verificar-manual -n curso --from=cronjob/verificar-web-periodico
kubectl wait -n curso --for=condition=Complete job/verificar-manual --timeout=120s
kubectl logs -n curso job/verificar-manual
```

O CronJob fornecido começa suspenso; criar um Job manual a partir dele permite validar o template sem esperar o calendário. Como exercício, ative-o por uma execução e suspenda novamente. Ao concluir, remova os dois recursos de batch com `kubectl delete -f laboratorios/02-workloads/extras/batch.yaml` e o Job manual com `kubectl delete job verificar-manual -n curso`. Não apague o namespace usado pelos próximos módulos.

## Exercício autônomo e rubrica

**Tempo: 90 minutos.** Em namespace `desafio-workloads`, implemente um serviço de sua escolha, compatível com a arquitetura: duas réplicas, ConfigMap, Service, requests/limits e as três probes. Prove atualização sem enviar tráfego ao backend não pronto. Crie um Job que confirme a resposta. Entregue YAML, evidência do cliente e um rollback reproduzível.

**Extensão, 30 minutos:** crie um DaemonSet de laboratório que apenas imprime hostname e aguarda. Use imagem fixa, recursos baixos e nenhum hostPath privilegiado. Quantos Pods aparecem? Explique por que o taint do CP pode excluir esse nó e remova somente o DaemonSet ao terminar.

**Rubrica, 10 pontos:** 2 para distinguir Pod/ReplicaSet/Deployment/Service; 2 para probes e recursos justificados; 2 para atualização e rollback; 2 para Job e teste de cliente; 2 para reconstrução sem copiar a solução. Exija 8/10 e aplicação restaurada. Pergunta de entrevista: “Por que Running não significa pronto para tráfego e por que rollback de Deployment não garante rollback da aplicação inteira?”

Fontes oficiais consultadas em **10/09/2026**. Próximo: [03 — Rede, Traefik, Ingress e Gateway API](03-rede.md).
