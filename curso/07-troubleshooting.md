# 07 — Diagnóstico por evidência e plantão simulado

## Antes de começar

Reserve **18–24 horas**: uma sessão para o método e os quatro primeiros casos, outra para storage/rede/memória e outra para repetir sem consultar a recuperação. Os módulos [01 — Control plane](01-control-plane.md), [02 — Workloads](02-workloads.md), [03 — Rede](03-rede.md), [04 — Storage](04-storage.md), [05 — Scheduling](05-scheduling.md) e [06 — Segurança](06-seguranca.md) são pré-requisitos: você já praticou os mecanismos que agora aparecerão com defeitos.

Use o cluster descartável kubeadm 1.35 com Calico, CoreDNS e workers Ready, kubectl instalado e contexto `curso-kubeadm`. Execute na **estação**, na raiz do repo. Somente comandos identificados como leitura no nó usam SSH; `crictl`, containerd e systemd já foram preparados no módulo 01. O caso OOM baixa uma imagem Python, e seu container terá memória limitada a 64 MiB. Não são necessárias ferramentas novas nem recursos AWS adicionais.

Os arquivos de [laboratorios/07-troubleshooting](../laboratorios/07-troubleshooting/) isolam as falhas em `curso-incidentes`. Não aplique todos de uma vez: alguns estão propositalmente errados. Falhas de control plane, etcd e desligamento físico não serão injetadas neste capítulo.

## O que você vai conseguir fazer

- Diferenciar falhas de imagem, processo, readiness, Service, scheduler, PVC, DNS e memória por evidências observáveis.
- Recuperar cada caso com uma mudança pequena e confirmar HTTP pelo mesmo caminho usado pelo cliente.
- Investigar kubelet/runtime com leitura por SSH quando a API não ajudar.
- Resolver três incidentes em 45 minutos e entregar um relato que separa sintoma, causa e prevenção.

Seu trabalho é reduzir incerteza sem destruir evidência. Para cada caso, anote horário, sintoma, impacto, duas hipóteses, teste discriminante, causa confirmada, correção e prevenção. Não vale "reiniciei e resolveu" sem explicar por quê. Não leia a recuperação antes de reservar 10–15 minutos ao diagnóstico.

## Preparação e estado saudável

```bash
kubectl config current-context
kubectl get nodes
kubectl apply -f laboratorios/07-troubleshooting/base.yaml
kubectl -n curso-incidentes rollout status deploy/web --timeout=120s
kubectl -n curso-incidentes wait --for=condition=Ready pod/diagnostico --timeout=120s
kubectl -n curso-incidentes exec diagnostico -- wget -T 3 -qO- http://web:8080
```

Esperado: `incidente-resolvido`. A base tem um Deployment de uma réplica com estratégia Recreate para deixar a indisponibilidade visível no serviço de treino; o pod separado `diagnostico` funciona como cliente. O servidor atende HTTP 8080 e usa readiness em `/`. `APP_MODE=servir` inicia httpd; `APP_MODE=falhar` escreve uma mensagem e sai com código 42. Esse contrato tornará possível distinguir erro de configuração de erro de infraestrutura.

Restabeleça HTTP **entre** incidentes; não acumule falhas inicialmente. Depois de qualquer correção do Deployment, execute `kubectl -n curso-incidentes rollout status deploy/web --timeout=120s` e repita o mesmo `wget`. Rollout concluído e resposta esperada são duas evidências complementares.

## Uma sequência que funciona no plantão

1. Confirme contexto/namespace e alcance do problema: uma réplica, um Service, um nó ou a API inteira?
2. Compare estado desejado e observado; veja último rollout e eventos antes de mudar algo.
3. Siga o caminho da requisição: DNS → Service/EndpointSlice → porta/probe do pod → aplicação.
4. Se o pod não executa, siga scheduler → montagem/configuração → pull → runtime → processo.
5. Faça uma mudança mínima, valide o resultado pelo ponto de vista do cliente e registre a causa.

```bash
kubectl config current-context
kubectl get nodes
kubectl -n curso-incidentes get deploy,rs,pods,svc,endpointslices
kubectl -n curso-incidentes get events --sort-by=.metadata.creationTimestamp
kubectl -n curso-incidentes describe pod NOME
kubectl -n curso-incidentes logs NOME --all-containers --tail=80
kubectl -n curso-incidentes logs NOME --previous --tail=80
```

Substitua `NOME` pelo pod atual obtido por `kubectl -n curso-incidentes get pods -l app=web-incidente`; o nome muda nos rollouts. `--previous` recupera o container anterior do mesmo pod; se não houve reinício, a ausência desse log é esperada. Excluir o pod pode eliminar a pista. Eventos expiram, e logs dependem de rotação. `Running` não significa Ready. `CrashLoopBackOff` é espera crescente entre reinícios, não o diagnóstico da causa.

Uma hipótese útil prevê uma diferença observável. “A rede quebrou” é ampla; “o Service tem selector errado” prevê DNS resolvendo, pods Ready e EndpointSlice sem backends. A hipótese alternativa “readiness falhando” prevê pods não Ready e eventos de probe, ainda que o endpoint também fique indisponível. Registre a previsão e escolha o teste que diferencia as duas antes de editar o YAML.

## Caso 1 — Release com imagem inexistente

Injete: `kubectl -n curso-incidentes set image deploy/web web=busybox:tag-inexistente-curso`.

Observe eventos do pod com `describe`. `manifest unknown`/`not found` aponta para referência inexistente; `unauthorized`/`denied` aponta para autenticação/autorização do registry; timeout ou resolução de nome aponta para acesso do **nó** ao registry; ausência de manifesto para a plataforma aponta para imagem sem a arquitetura do nó. Não há logs de aplicação se o container nunca iniciou. Neste caso a tag inventada é a causa esperada; `ImagePullBackOff` é o mecanismo de novas tentativas espaçadas.

Use `kubectl -n curso-incidentes get deployment web -o jsonpath='{.spec.template.spec.containers[0].image}'` para comprovar a referência desejada e `kubectl -n curso-incidentes rollout history deployment/web` para localizar a mudança. O DNS que resolve nomes de Services para pods não é o mesmo caminho de acesso usado pelo runtime para buscar a imagem.

<details><summary>Recuperação e prova</summary>

Execute `kubectl -n curso-incidentes set image deploy/web web=busybox:1.37.0`, aguarde rollout e teste HTTP novamente. Documente o evento original e a imagem corrigida. Em operação, selecione versão/digest validado pelo pipeline, não uma tag qualquer que "puxa".

</details>

## Caso 2 — Processo encerra

Injete: `kubectl -n curso-incidentes set env deployment/web APP_MODE=falhar`.

Espere um reinício e examine `logs --previous`. Para estado da execução anterior, use `kubectl -n curso-incidentes get pod NOME -o jsonpath='{.status.containerStatuses[0].lastState.terminated}'`. Compare `reason`, `exitCode`, `startedAt` e `finishedAt`. O processo imprime a causa sintética e sai com código 42. Isso confirma que houve execução e descarta falha de pull como causa deste caso. Não altere probes para esconder uma saída do processo.

<details><summary>Recuperação e prova</summary>

Execute `kubectl -n curso-incidentes set env deployment/web APP_MODE=servir`. Aguarde rollout, valide HTTP e compare restartCount do pod novo. Explique como um Secret/ConfigMap inválido poderia produzir sintoma semelhante, mas necessitaria investigar a configuração do processo.

</details>

## Caso 3 — Pod Running, serviço sem resposta

Injete:

```bash
kubectl -n curso-incidentes patch deployment web --type=strategic \
  -p '{"spec":{"template":{"spec":{"containers":[{"name":"web","readinessProbe":{"httpGet":{"path":"/inexistente","port":"http"}}}]}}}}'
```

Compare Ready, restartCount, eventos da probe e `kubectl -n curso-incidentes get endpointslice -l kubernetes.io/service-name=web -o yaml`. O servidor pode responder em `/` diretamente no Pod IP enquanto o endpoint fica indisponível para o Service. Para testar a hipótese, obtenha IP com `kubectl -n curso-incidentes get pods -l app=web-incidente -o wide`, depois use `kubectl -n curso-incidentes exec diagnostico -- wget -T 3 -qO- http://IP_REAL_DO_POD:8080/`. Readiness deve falhar, sem aumento do restartCount por essa probe. O teste final continua pelo Service; acessar o IP só discrimina a causa.

<details><summary>Recuperação e prova</summary>

```bash
kubectl -n curso-incidentes patch deployment web --type=strategic \
  -p '{"spec":{"template":{"spec":{"containers":[{"name":"web","readinessProbe":{"httpGet":{"path":"/","port":"http"}}}]}}}}'
kubectl -n curso-incidentes rollout status deploy/web --timeout=120s
kubectl -n curso-incidentes exec diagnostico -- wget -T 3 -qO- http://web:8080
```

Confirme endpoint com `conditions.ready: true`. Readiness retira tráfego; liveness pode reiniciar processo; startup adia avaliação das outras probes durante inicialização. Não trate as três como equivalentes.

</details>

## Caso 4 — Service com selector incorreto

Injete: `kubectl -n curso-incidentes patch service web --type=merge -p '{"spec":{"selector":{"app":"web-inexistente"}}}'`.

O Service existe e DNS resolve, mas não seleciona os pods. Confira `kubectl -n curso-incidentes get pods --show-labels`, selector e EndpointSlices. Fazer port-forward no Deployment pode funcionar e ainda deixar o incidente aberto.

<details><summary>Recuperação e prova</summary>

Execute `kubectl -n curso-incidentes patch service web --type=merge -p '{"spec":{"selector":{"app":"web-incidente"}}}'`. Confirme EndpointSlice preenchido e HTTP pelo pod de diagnóstico. Como variação posterior, um `targetPort` errado preserva os backends selecionados, mas manda tráfego à porta incorreta: EndpointSlice existente não prova processo ouvindo.

</details>

## Caso 5 — Pending antes de iniciar

Injete: `kubectl -n curso-incidentes patch deployment web --type=merge -p '{"spec":{"template":{"spec":{"nodeSelector":{"curso.incidente":"ninguem"}}}}}'`.

O pod ainda não tem nodeName. Investigue eventos, labels dos nós e taints; não procure logs de um container que nunca iniciou. Compare com um Pending causado por requests insuficientes no módulo 05.

<details><summary>Recuperação e prova</summary>

Remova o campo com `kubectl -n curso-incidentes patch deployment web --type=merge -p '{"spec":{"template":{"spec":{"nodeSelector":null}}}}'`. Reaplicar um manifesto que nunca gerenciou esse campo não é garantia de removê-lo. Verifique scheduling, rollout e HTTP.

</details>

## Caso 6 — Volume nunca provisionado

```bash
kubectl apply -f laboratorios/07-troubleshooting/pvc-pendente.yaml
kubectl -n curso-incidentes get pod espera-volume
kubectl -n curso-incidentes describe pvc volume-ausente
kubectl get storageclass
```

O PVC pede uma classe chamada `classe-que-nao-existe`; como ela não existe, não há definição de provisioner para satisfazer o pedido. `spec.volumeName` vazio significa que não ocorreu binding. Use o quadro para diferenciar sintomas que também podem deixar um pod esperando:

| Evidência | Interpretação e próximo teste |
| --- | --- |
| StorageClass ausente | Nome incorreto ou instalação não feita; compare `storageClassName` ao inventário |
| Evento aguardando primeiro consumidor | `WaitForFirstConsumer` pode estar funcionando; procure Pod consumidor e restrições de agendamento |
| Evento `UnauthorizedOperation` do CSI | Houve tentativa de API AWS; investigue identidade e ARN conforme módulo 04 |
| PV Bound com node affinity incompatível | Compare AZ/hostname do PV aos nós; não existe mudança de zona por editar label |
| PV Bound e erro de attach/mount | Examine eventos do pod, `kubectl get volumeattachment` e logs do CSI; binding não garante montagem |

No laboratório atual, comprovar classe ausente basta. Você não precisa criar discos nem abrir um projeto externo para concluir a distinção.

<details><summary>Recuperação e prova</summary>

```bash
kubectl -n curso-incidentes get pvc volume-ausente -o jsonpath='{.spec.volumeName}'
kubectl -n curso-incidentes delete pod espera-volume
kubectl -n curso-incidentes delete pvc volume-ausente
```

Confirme ausência de vínculo antes de excluir. Para corrigir o pedido em uma aplicação que precisa desses dados, recrie o PVC com a StorageClass já implementada no módulo 04; campos de binding não são livremente editáveis. A correção funcional já foi praticada naquele pré-requisito. Aqui a entrega é identificar por que este pedido não poderia funcionar e retirar apenas os objetos sem dados.

</details>

## Caso 7 — DNS falha após política

Injete `kubectl apply -f laboratorios/07-troubleshooting/bloquear-diagnostico.yaml`. A regra seleciona `papel: diagnostico`, isola egress e não concede destinos. Logo pode bloquear DNS e HTTP mesmo com servidores saudáveis.

```bash
kubectl -n curso-incidentes exec diagnostico -- nslookup web
kubectl -n curso-incidentes exec diagnostico -- cat /etc/resolv.conf
kubectl -n curso-incidentes get networkpolicy bloquear-diagnostico -o yaml
kubectl -n kube-system get pods -l k8s-app=kube-dns
kubectl -n kube-system get service kube-dns
```

Espere timeout no cliente e CoreDNS ainda saudável. Isso localiza a diferença no caminho da origem. Reiniciar CoreDNS não removeria a política.

<details><summary>Recuperação e prova</summary>

Remova somente `kubectl -n curso-incidentes delete networkpolicy bloquear-diagnostico`. DNS e HTTP devem voltar. Depois construa uma política restritiva correta, permitindo DNS TCP/UDP53 e egress ao web, usando o aprendizado do módulo 06.

</details>

## Caso 8 — OOM no container, não falta global de RAM

A imagem Python da base executa um processo que espera cinco segundos e tenta alocar 128 MiB, mas seu cgroup permite apenas 64 MiB. Isso provoca uma falha limitada ao container do exercício, não uma tentativa de esgotar a RAM da máquina.

```bash
kubectl apply -f laboratorios/07-troubleshooting/oom.yaml
kubectl -n curso-incidentes get pod oom-treino -w
# Após observar reinício, interrompa só a observação com Ctrl+C.
kubectl -n curso-incidentes describe pod oom-treino
kubectl -n curso-incidentes get pod oom-treino \
  -o jsonpath='{.status.containerStatuses[0].lastState.terminated}'
```

Espere `OOMKilled`, normalmente exit code137, e restartCount crescente. O código 137 isolado também pode indicar outro SIGKILL; `reason` e limite de memória dão contexto. `kubectl top` pode perder o pico por amostragem; valor baixo não refuta OOM anterior. Recupere com `kubectl -n curso-incidentes delete pod oom-treino` após guardar dados. Como correção de uma aplicação real, investigue vazamento, quantidade de trabalho e limite adequado; aumentar RAM sem medir não identifica a causa.

## Quando a API ou o nó não responde

Estes comandos são **leitura via SSH no nó afetado**; não provocam falha:

```bash
sudo systemctl status kubelet containerd --no-pager
sudo journalctl -u kubelet --since '-15 min' --no-pager
sudo journalctl -u containerd --since '-15 min' --no-pager
sudo crictl --runtime-endpoint unix:///run/containerd/containerd.sock ps -a
sudo crictl --runtime-endpoint unix:///run/containerd/containerd.sock info
df -h
df -i
free -h
sudo ss -lntp
```

`systemctl` confirma o serviço; `journalctl` revela mensagens de inicialização/conexão; `crictl ps -a` lista containers inclusive encerrados; `df -h` mede bytes livres, enquanto `df -i` mede inodes. Pode faltar inode mesmo com GiB disponíveis. `free` descreve memória do host e não substitui investigar o cgroup de um container.

No control plane, examine `/etc/kubernetes/manifests`, certificados e containers estáticos. Com ID obtido em `crictl ps -a`, `sudo crictl --runtime-endpoint unix:///run/containerd/containerd.sock logs ID_EXATO` funciona sem API Server; `kubectl logs` depende dele. Não edite um static pod antes de copiar seu manifesto **para fora** do diretório observado pelo kubelet. Uma cópia `.bak` dentro desse diretório pode ser interpretada como outro manifesto.

O resumo `NotReady` pode corresponder a `Ready=False` ou a `Ready=Unknown`. `False` costuma acompanhar uma condição reportada pelo kubelet, como CRI/CNI não pronto; `Unknown` indica que o control plane deixou de receber informação recente. Kubelet parado pode levar ao segundo caso. Compare `kubectl describe node NOME` e `kubectl -n kube-node-lease get lease NOME -o yaml`: `renewTime` ajuda a localizar o último heartbeat, mas não comprova sozinho a causa da perda.

Eviction por pressão de disco é uma decisão do kubelet sobre o nó; OOM do container é um evento de memória do processo/cgroup. Nesta seção só é exigido associar cada evidência à camada e coletar leitura de um nó saudável. A falha de kubelet já foi praticada no módulo 01. Reiniciar runtime, retirar static pods e recuperar API exigem as condições do [08 — Manutenção](08-manutencao.md), não improvisação durante este exercício.

## Simulado independente

Peça a um colega que aplique três casos em ordem desconhecida somente neste namespace, ou sorteie números antes de fechar esta página. Meta: **45 minutos**, com um relatório por incidente, sem excluir namespace nem reinstalar cluster. Use os mecanismos praticados e ajuda local quando necessário: por exemplo, `kubectl explain service.spec.selector` responde qual campo seleciona backends; `kubectl logs --help` esclarece a opção de container anterior. A consulta termina ao responder aquela pergunta. Documentação externa permanece uma opção de aprofundamento, não um requisito para resolver os casos.

Depois repita com uma combinação, como selector errado mais readiness quebrada. Corrigir o primeiro defeito pode não recuperar o serviço; o critério de término continua sendo o teste do cliente, não apenas o desaparecimento de uma mensagem.

Rubrica, 10 pontos: evidência antes da mudança (3), causa diferenciada de sintoma (2), correção mínima (2), prova pelo cliente e prevenção (2), dentro do tempo (1). Após registrar evidências, a limpeza é `kubectl delete namespace curso-incidentes`; isso remove exclusivamente o ambiente de treino.

## Fechamento

Você investigou etapas diferentes do caminho entre intenção e serviço disponível. Antes de avançar, explique: por que não há log de aplicação em falha de pull? Como separar selector incorreto de readiness falhando? Por que volume Bound ainda pode não montar? O que distingue timeout do cliente de CoreDNS indisponível? Qual evidência adicional dá significado ao exit code137?

Conclua com **8/10 em duas sessões**, aplicação recuperada e três relatos de causa/teste/correção. O curso não exige provocar falha global de nó ou recuperar etcd nesta aula. O próximo capítulo, [08 — Manutenção](08-manutencao.md), amplia o escopo de mudanças com backup, janela e procedimento explícito de retorno.

## Referências opcionais

- [Diagnóstico de aplicações](https://kubernetes.io/docs/tasks/debug/debug-application/) — amplia a classificação de falhas além dos oito casos praticados.
- [Diagnóstico de Pods](https://kubernetes.io/docs/tasks/debug/debug-application/debug-pods/) — aprofunda estados, eventos e coleta de informações de containers.
- [Diagnóstico de Services](https://kubernetes.io/docs/tasks/debug/debug-application/debug-service/) — expande testes de endpoints, portas e dataplane.
- [Diagnóstico de DNS](https://kubernetes.io/docs/tasks/administer-cluster/dns-debugging-resolution/) — detalha configuração e logs de CoreDNS para cenários além da política de rede.
- [crictl](https://kubernetes.io/docs/tasks/debug/debug-cluster/crictl/) — apresenta inspeções CRI adicionais quando a API está indisponível.
- [Memória de containers](https://kubernetes.io/docs/tasks/configure-pod-container/assign-memory-resource/) — aprofunda requests, limits e comportamento de OOM.
