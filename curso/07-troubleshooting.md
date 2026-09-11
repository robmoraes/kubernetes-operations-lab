# 07 — Diagnóstico por evidência e plantão simulado

Reserve **18–24 horas**. Precisa dos módulos 01–06. Execute os exercícios na **estação**, dentro do repo e no contexto do cluster descartável. Somente os exercícios explicitamente marcados como leitura no nó usam SSH. Todas as falhas de aplicação ficam em `curso-incidentes`.

Seu trabalho é reduzir incerteza sem destruir evidência. Para cada caso, anote horário, sintoma, impacto, duas hipóteses, teste discriminante, causa confirmada, correção e prevenção. Não vale "reiniciei e resolveu" sem explicar por quê. Não leia a recuperação antes de reservar 10–15 minutos ao diagnóstico.

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

`--previous` recupera o container anterior do mesmo pod; excluir o pod pode eliminar essa pista. Eventos expiram, e logs dependem de rotação. `Running` não significa Ready. `CrashLoopBackOff` é espera crescente entre reinícios, não o diagnóstico da causa.

## Preparação e estado saudável

```bash
kubectl apply -f laboratorios/07-troubleshooting/base.yaml
kubectl -n curso-incidentes rollout status deploy/web --timeout=120s
kubectl -n curso-incidentes wait --for=condition=Ready pod/diagnostico --timeout=120s
kubectl -n curso-incidentes exec diagnostico -- wget -T 3 -qO- http://web:8080
```

Esperado: `incidente-resolvido`. Há uma réplica com estratégia Recreate para deixar as falhas visíveis no serviço de treino. Restabeleça esse resultado **entre** incidentes; não acumule falhas inicialmente. Todos os nomes nas mutações são exclusivos do módulo.

## Caso 1 — Release com imagem inexistente

Injete: `kubectl -n curso-incidentes set image deploy/web web=busybox:tag-inexistente-curso`.

Observe eventos do pod. Diferencie registry inacessível, `unauthorized`, tag ausente e arquitetura incompatível; cada um pede uma solução. Consulte Deployment/ReplicaSet e compare imagem anterior. `ImagePullBackOff` não é erro de DNS do Service.

<details><summary>Recuperação e prova</summary>

Execute `kubectl -n curso-incidentes set image deploy/web web=busybox:1.37.0`, aguarde rollout e teste HTTP novamente. Documente o evento original e a imagem corrigida. Em operação, selecione versão/digest validado pelo pipeline, não uma tag qualquer que "puxa".

</details>

## Caso 2 — Processo encerra

Injete: `kubectl -n curso-incidentes set env deployment/web APP_MODE=falhar`.

Espere um reinício e examine `logs --previous`, exitCode e lastState. O processo imprime a causa sintética e sai com código 42. Confirme que container chegou a iniciar; isso descarta erro de pull. Não altere probes para esconder uma saída do processo.

<details><summary>Recuperação e prova</summary>

Execute `kubectl -n curso-incidentes set env deployment/web APP_MODE=servir`. Aguarde rollout, valide HTTP e compare restartCount do pod novo. Explique como um Secret/ConfigMap inválido poderia produzir sintoma semelhante, mas necessitaria investigar a configuração do processo.

</details>

## Caso 3 — Pod Running, serviço sem resposta

Injete:

```bash
kubectl -n curso-incidentes patch deployment web --type=strategic \
  -p '{"spec":{"template":{"spec":{"containers":[{"name":"web","readinessProbe":{"httpGet":{"path":"/inexistente","port":"http"}}}]}}}}'
```

Compare Ready, restartCount, eventos da probe e EndpointSlices. O servidor pode responder em `/` diretamente no Pod IP enquanto o endpoint fica indisponível para o Service. O cliente deve continuar testando pelo Service para validar impacto real.

<details><summary>Recuperação e prova</summary>

Troque somente `path` de volta a `/` usando o mesmo patch, aguarde rollout e confirme endpoint com `conditions.ready: true`. Readiness retira tráfego; liveness pode reiniciar processo; startup adia avaliação das outras probes durante inicialização. Não trate as três como equivalentes.

</details>

## Caso 4 — Service com selector incorreto

Injete: `kubectl -n curso-incidentes patch service web --type=merge -p '{"spec":{"selector":{"app":"web-inexistente"}}}'`.

O Service existe e DNS resolve, mas não seleciona os pods. Confira `kubectl -n curso-incidentes get pods --show-labels`, selector e EndpointSlices. Fazer port-forward no Deployment pode funcionar e ainda deixar o incidente aberto.

<details><summary>Recuperação e prova</summary>

Use o mesmo patch com `"app":"web-incidente"`. Confirme EndpointSlice preenchido e HTTP pelo pod de diagnóstico. Para outro cenário, deixe selector certo e altere `targetPort`: a camada defeituosa será diferente, mesmo com sintoma parecido.

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

Não há provisioner para a classe `classe-que-nao-existe`. Compare com WaitForFirstConsumer legítimo, erro IAM do CSI, volume em AZ incompatível e anexo pendente. Aplique os comandos de diagnóstico dos quatro casos conceitualmente, sem criar discos desnecessários.

<details><summary>Recuperação e prova</summary>

Estes objetos nunca obtiveram PV, então confirme `spec.volumeName` vazio e remova somente `pod/espera-volume` e `pvc/volume-ausente`. Para corrigir de verdade, recrie o PVC com uma StorageClass existente e autorizada; campos de binding não são livremente editáveis. Reproduza a correção com o lab de storage e documente quando ela cria EBS cobrado.

</details>

## Caso 7 — DNS falha após política

Injete `kubectl apply -f laboratorios/07-troubleshooting/bloquear-diagnostico.yaml`. Teste `nslookup web`, compare `/etc/resolv.conf`, leia políticas e confira saúde de CoreDNS antes de reiniciá-lo. A regra isola egress só do pod diagnóstico.

<details><summary>Recuperação e prova</summary>

Remova somente `kubectl -n curso-incidentes delete networkpolicy bloquear-diagnostico`. DNS e HTTP devem voltar. Depois construa uma política restritiva correta, permitindo DNS TCP/UDP53 e egress ao web, usando o aprendizado do módulo 06.

</details>

## Caso 8 — OOM no container, não falta global de RAM

Aplique `laboratorios/07-troubleshooting/oom.yaml`: o processo pede um bloco de memória maior que seu limit, dentro de um pod pequeno e isolado. Observe `lastState.terminated.reason`, exit code, limits e reinícios. `kubectl top` pode perder o pico por amostragem; um valor baixo não refuta um OOM anterior. Recupere excluindo apenas `pod/oom-treino` após guardar os dados. Como correção de aplicação, avalie vazamento, volume de trabalho e limit adequado; aumentar RAM sem medir não é diagnóstico.

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

No control plane, examine `/etc/kubernetes/manifests`, certificados e containers estáticos. `crictl logs ID_EXATO` funciona sem API Server; `kubectl logs` depende dele. Não edite um static pod antes de copiar seu manifesto **para fora** do diretório observado pelo kubelet. Uma cópia `.bak` dentro desse diretório pode ser interpretada como outro manifesto.

`NotReady` pode refletir kubelet parado, CRI indisponível ou CNI não pronto. `Unknown` pode refletir perda de heartbeat/rede. Correlacione com `kubectl describe node`, Lease em `kube-node-lease`, conectividade TCP6443 e logs. Eviction por disk pressure difere de OOM do container. Para reiniciar runtime ou desconectar um nó deliberadamente, agende um exercício separado, conheça os pods afetados e use o runbook de manutenção.

## Simulado independente

Peça a um colega que aplique três casos em ordem desconhecida somente neste namespace, ou sorteie números antes de fechar esta página. Meta: **45 minutos**, com um relatório por incidente, sem excluir namespace nem reinstalar cluster. Pode usar documentação oficial; avalie precisão e tempo de navegação, não memorização cega. Depois repita com uma combinação, por exemplo selector errado mais readiness quebrada.

Rubrica, 10 pontos: evidência antes da mudança (3), causa diferenciada de sintoma (2), correção mínima (2), prova pelo cliente e prevenção (2), dentro do tempo (1). Avance com 8/10 em duas sessões diferentes. Após registrar evidências, a limpeza é `kubectl delete namespace curso-incidentes`; isso remove exclusivamente o ambiente de treino.

Fontes consultadas em 10/09/2026: [debug de aplicações](https://kubernetes.io/docs/tasks/debug/debug-application/), [debug de pods](https://kubernetes.io/docs/tasks/debug/debug-application/debug-pods/), [debug de Services](https://kubernetes.io/docs/tasks/debug/debug-application/debug-service/), [DNS](https://kubernetes.io/docs/tasks/administer-cluster/dns-debugging-resolution/), [crictl](https://kubernetes.io/docs/tasks/debug/debug-cluster/crictl/), [recursos de memória](https://kubernetes.io/docs/tasks/configure-pod-container/assign-memory-resource/).
