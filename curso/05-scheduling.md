# 05 — Agendamento, capacidade e disponibilidade

**Duração:** 18–24 horas, incluindo preparação de certificados e observação do autoscaling. Faça pausas entre Pending, manutenção e métricas; cada etapa termina com a restauração de seu estado.

## Antes de começar

Conclua [02 — Workloads](02-workloads.md) e [03 — Rede](03-rede.md): você precisa entender requests/limits, labels, readiness, Services e Helm. Use Kubernetes 1.35 com dois workers Ready e capacidade para quatro Pods pequenos. O laboratório é `curso-scheduling`; os workloads de storage/CSI do módulo 04 devem continuar operacionais caso ainda existam. Nenhum comando de drain deve atingir um nó de produção.

Os comandos são **LOCAL**, na raiz do repositório e com o kubeconfig do curso. Helm 4.2.3 e OpenSSL foram preparados no módulo 03. Você também terá sessões **HOST CP/WORKER** com sudo para configurar os kubelets, um por vez. AWS CLI não é necessária para este módulo; em EC2, você precisa poder revisar os Security Groups dos nós. Os manifests estão em [laboratorios/05-scheduling](../laboratorios/05-scheduling/).

```bash
kubectl config current-context
kubectl get nodes -L kubernetes.io/hostname,topology.kubernetes.io/zone
read -r -p 'Nome Kubernetes do primeiro worker do laboratório: ' WORKER_1
read -r -p 'Nome Kubernetes do segundo worker do laboratório: ' WORKER_2
kubectl get node "$WORKER_1" "$WORKER_2"
```

Confirme nomes distintos, Ready e ausência de manutenção prévia. Não remova taints ou labels que você não criou. Se um worker abriga o controller EBS com identidade associada ao nó, mantenha esse controller fora dos testes de reinício/eviction da aplicação.

## O que você vai conseguir fazer

- Explicar por evidências a diferença entre falta de recursos solicitáveis e uma restrição impossível.
- Usar seletor, toleration, affinity e distribuição de topologia em exemplos pequenos.
- Observar PDB bloqueando e permitindo eviction, sem confundir isso com proteção contra pane de nó.
- Preparar certificados serving dos kubelets, instalar Metrics Server com TLS validado e obter métricas.
- Configurar HPA, provocar carga limitada, observar subida/descida e restaurar o laboratório.

## Como o scheduler escolhe um nó

O scheduler procura nós elegíveis para Pods sem `spec.nodeName`. Primeiro elimina candidatos incompatíveis com requests, taints, seletores, afinidades, volumes e topologia; depois pontua os restantes. A decisão usa recursos **solicitados**, não apenas CPU/RAM usados naquele instante. `kubectl describe node` mostra requests alocados; `kubectl top`, disponível depois de instalar métricas, mostra uso recente. Um nó ocioso pode estar cheio de reservas feitas por outros Pods.

O pedido é diferente do limite: request orienta colocação e partilha; limit restringe execução. CPU acima do limite sofre throttling, memória acima do limite pode provocar OOMKill. Um Pod que nem foi agendado ainda não consumiu a CPU que pediu. Isso torna um request exagerado uma falha segura para estudar Pending sem esgotar memória de verdade.

| Mecanismo | Regra implementada | Limite |
| --- | --- | --- |
| nodeSelector / node affinity required | Exige labels num nó | Não cria a label ou capacidade ausente |
| node affinity preferred | Aumenta a preferência | Não garante colocação exclusiva |
| taint / toleration | Nó repele; Pod pode tolerar | Tolerar não obriga usar aquele nó |
| pod anti-affinity | Considera localização de outros Pods | Se obrigatória, pode impedir réplicas extras |
| topology spread | Reduz desequilíbrio entre domínios | Depende de labels de topologia reais |
| PDB | Orçamento para interrupções voluntárias via eviction | Não impede pane de EC2 nem delete direto de Pod |

`IgnoredDuringExecution` significa que mudar uma label depois do agendamento não expulsa automaticamente o Pod existente. Taint `NoSchedule` afeta novos Pods; `NoExecute` também pode expulsar os existentes sem toleration correspondente. `spec.nodeName` atribui o nó diretamente, pulando a seleção normal, por isso não será nossa correção para Pending.

## 1. Requests e restrições impossíveis

```bash
kubectl describe node "$WORKER_1"
kubectl apply -f laboratorios/05-scheduling/base.yaml
kubectl -n curso-scheduling rollout status deployment/agenda --timeout=120s
kubectl -n curso-scheduling get pods -o wide
```

A base pede 50m de CPU por réplica, limita a 500m e usa duas réplicas. `topologySpreadConstraints` seleciona `app=agenda`, compara o domínio `kubernetes.io/hostname` e prefere diferença máxima de uma réplica (`maxSkew: 1`). `ScheduleAnyway` permite uma colocação menos equilibrada se necessário: disponibilidade de capacidade prevalece sobre uma proibição rígida. Não inventamos três zonas num cluster de uma AZ.

```bash
kubectl -n curso-scheduling set resources deployment/agenda --requests=cpu=100,memory=256Mi --limits=cpu=100,memory=512Mi
kubectl -n curso-scheduling get pods
kubectl -n curso-scheduling describe pods -l app=agenda
kubectl -n curso-scheduling get events --sort-by=.metadata.creationTimestamp
```

`100` é cem CPUs; `100m` seria um décimo de CPU. Espere `Insufficient cpu` nos eventos de scheduling dos novos Pods. Os antigos podem continuar atendendo durante o rollout: confira `kubectl get replicasets -n curso-scheduling` para separar revisões. **Recuperação:** reaplique `base.yaml` e aguarde `rollout status`. A evidência é o evento causal mais uma aplicação restaurada, não somente a imagem de um Pending.

Agora use um seletor que não corresponde a nenhum nó:

```bash
kubectl -n curso-scheduling patch deployment agenda --type=merge -p '{"spec":{"template":{"spec":{"nodeSelector":{"curso.pool":"inexistente"}}}}}'
kubectl -n curso-scheduling describe pods -l app=agenda
kubectl -n curso-scheduling patch deployment agenda --type=merge -p '{"spec":{"template":{"spec":{"nodeSelector":null}}}}'
kubectl -n curso-scheduling rollout status deployment/agenda --timeout=180s
```

Espere evento de incompatibilidade de node selector/affinity. O patch com `null` remove só esse campo; ele não muda labels de nós. Compare esse diagnóstico com Insufficient cpu: aumentar uma EC2 não resolve um seletor que nenhum nó possui.

## 2. Toleration e affinity, cada uma com sua responsabilidade

Antes de alterar o primeiro worker, liste o que roda nele: `kubectl get pods -A -o wide --field-selector spec.nodeName="$WORKER_1"`. `NoSchedule` não remove os Pods existentes, mas pode impedir sua substituição durante a janela; isso inclui addons fixados nesse nó. Este exercício altera somente o Deployment agenda e termina removendo o taint.

```bash
kubectl taint node "$WORKER_1" curso=manutencao:NoSchedule
kubectl -n curso-scheduling rollout restart deployment/agenda
kubectl -n curso-scheduling rollout status deployment/agenda --timeout=180s
kubectl -n curso-scheduling get pods -o wide
```

Com capacidade no segundo worker, os novos Pods irão para ele. Agora abra [colocacao-patch.yaml](../laboratorios/05-scheduling/colocacao-patch.yaml). A toleration corresponde exatamente à chave `curso`, valor `manutencao` e efeito `NoSchedule`, permitindo passar pela barreira. A node affinity required exige a label `curso.scheduling/alvo=true`; só marcaremos o worker escolhido. Juntas, as regras permitem e direcionam. Não reservam esse nó para sempre nem impedem que outros Pods com toleration compatível o usem.

```bash
kubectl label node "$WORKER_1" curso.scheduling/alvo=true
kubectl patch deployment agenda -n curso-scheduling --type=strategic --patch-file laboratorios/05-scheduling/colocacao-patch.yaml
kubectl -n curso-scheduling rollout status deployment/agenda --timeout=180s
kubectl -n curso-scheduling get pods -o wide
```

Espere duas réplicas no worker marcado, apesar do taint; a preferência de spread não sobrepõe a afinidade obrigatória. Se não houver espaço para o rollout nesse nó, ele ficará Pending: a toleration não cria CPU. Para restaurar, retire somente nossos campos/marcações:

```bash
kubectl patch deployment agenda -n curso-scheduling --type=merge -p '{"spec":{"template":{"spec":{"affinity":null,"tolerations":null}}}}'
kubectl taint node "$WORKER_1" curso=manutencao:NoSchedule-
kubectl label node "$WORKER_1" curso.scheduling/alvo-
kubectl apply -f laboratorios/05-scheduling/base.yaml
kubectl -n curso-scheduling rollout status deployment/agenda --timeout=180s
```

## 3. PDB e manutenção com eviction

Um PDB conta Pods saudáveis selecionados por label e calcula quantos podem ser interrompidos voluntariamente. Com duas réplicas Ready e `minAvailable: 2`, não sobra nenhuma interrupção permitida. **Eviction** é a requisição que respeita esse orçamento; drain usa essa API. `kubectl delete pod` é outro caminho e não serve para provar que o PDB funcionou.

```bash
kubectl apply -f laboratorios/05-scheduling/pdb-bloqueio.yaml
kubectl -n curso-scheduling get pdb
kubectl -n curso-scheduling get pods -o wide
read -r -p 'Worker que realmente hospeda pelo menos um Pod agenda: ' DRAIN_NODE
kubectl drain "$DRAIN_NODE" --ignore-daemonsets --pod-selector app=agenda --timeout=45s
```

O timeout é esperado e `ALLOWED DISRUPTIONS` deve ser zero. Esse drain **parcial** cordona o nó e tenta retirar somente `app=agenda`; não prepara a máquina inteira para desligamento. Não use `--disable-eviction` ou `--force` para contornar a experiência. Mesmo após timeout, o nó continua cordonado e precisa ser liberado quando terminar.

```bash
kubectl -n curso-scheduling patch pdb agenda --type=merge -p '{"spec":{"minAvailable":1}}'
kubectl drain "$DRAIN_NODE" --ignore-daemonsets --pod-selector app=agenda --timeout=180s
kubectl -n curso-scheduling rollout status deployment/agenda --timeout=180s
kubectl -n curso-scheduling get pods -o wide
kubectl uncordon "$DRAIN_NODE"
```

Espere a réplica substituta Ready antes de concluir. Em manutenção real, é preciso revisar **todos** os Pods, PDBs, volumes e capacidade de destino; o drain seria sem seletor. `--ignore-daemonsets` permite prosseguir sem tentar apagar agentes mantidos por DaemonSet. `emptyDir` requer uma decisão explícita sobre perda de dados antes de `--delete-emptydir-data`. Uncordon só reabre o nó para futuros agendamentos; não redistribui automaticamente as réplicas atuais. No exercício, nenhuma máquina será desligada.

## 4. Por que HPA precisa de uma API de métricas

HPA de CPU compara consumo com request e altera o número de réplicas do alvo. Para request de 50m e alvo de 50%, a referência é 25m por réplica. De forma simplificada, calcula `ceil(réplicas atuais × utilização observada / alvo)`, respeitando limites, tolerâncias e janelas. Um request ausente impede calcular a utilização dessa forma. O HPA cria Pods; não cria EC2. Um node autoscaler é outro componente e não surge automaticamente em kubeadm.

**Metrics Server** coleta CPU/memória recentes dos kubelets e os oferece pela API agregada `metrics.k8s.io`. O objeto **APIService** registra que chamadas dessa API devem ser encaminhadas ao serviço Metrics Server. Isso não é histórico de observabilidade; `kubectl top` e o HPA precisam dessa coleta recente para funcionar.

Há duas conexões de rede/TLS a preparar: API Server → Service Metrics Server (443, encaminhado ao container 10250) e Metrics Server → IP interno de cada kubelet (10250). Calico deve permitir o primeiro caminho e Security Groups/firewalls devem permitir 10250 a partir dos nós que hospedam Metrics Server. No laboratório EC2, acrescente entrada TCP 10250 com origem **SG dos workers do cluster** nos SGs dos nós consultados; mantenha a origem do CP já existente, sem abrir à Internet. Tokens/RBAC autenticam as requisições; certificados válidos identificam os servidores.

## 5. Certificados serving dos kubelets

O kubelet já possui um certificado **cliente** para falar com a API. Ele precisa também de um certificado **servidor**, apresentado em HTTPS 10250. Kubeadm pode iniciar esse segundo certificado como autoassinado. `serverTLSBootstrap: true` faz o kubelet solicitar um certificado serving à API; o signer `kubernetes.io/kubelet-serving` só o emite depois de aprovação. Habilitar a solicitação não significa aprová-la automaticamente.

Uma **CSR**, Certificate Signing Request, contém a chave pública e a identidade que se pede para certificar; a chave privada fica no nó. O signer identifica as regras e a autoridade que assinarão o certificado. Aprovar uma CSR declara que sua identidade foi conferida; por isso precisamos examinar solicitante, nome do nó, usos e SANs antes de aprová-la.

Primeiro preserve a configuração compartilhada e adicione o campo **dentro** do documento KubeletConfiguration guardado em `data.kubelet`, não como um campo externo do ConfigMap:

```bash
# LOCAL
SCHED_DIR=$(mktemp -d)
kubectl get configmap kubelet-config -n kube-system -o yaml > "$SCHED_DIR/kubelet-config-antes.yaml"
kubectl edit configmap kubelet-config -n kube-system
```

Localize a seção abaixo e acrescente apenas a última linha no documento existente, mantendo todas as demais chaves. Este fragmento ilustra a indentação; não substitui o ConfigMap inteiro:

```yaml
data:
  kubelet: |
    apiVersion: kubelet.config.k8s.io/v1beta1
    kind: KubeletConfiguration
    serverTLSBootstrap: true
```

A configuração compartilhada orienta futuros joins/upgrades, mas não reescreve imediatamente o arquivo de cada host. **HOST CP e cada HOST WORKER, um de cada vez**, faça a alteração local correspondente:

```bash
hostname
sudo test ! -e /var/lib/kubelet/config.yaml.before-serving-tls && sudo cp -a /var/lib/kubelet/config.yaml /var/lib/kubelet/config.yaml.before-serving-tls
sudoedit /var/lib/kubelet/config.yaml
# Acrescente serverTLSBootstrap: true como chave de primeiro nível, sem duplicá-la.
sudo systemctl restart kubelet
sudo systemctl is-active kubelet
sudo journalctl -u kubelet -n 50 --no-pager
```

Se o backup já existir, confirme que pertence à sua configuração inicial; não o sobrescreva. Após cada nó, **LOCAL** espere Ready com `kubectl wait --for=condition=Ready node/NOME_REAL --timeout=180s` e examine sua CSR antes de alterar o próximo. Se o kubelet falhar por YAML inválido, **no mesmo host** restaure `sudo cp -a /var/lib/kubelet/config.yaml.before-serving-tls /var/lib/kubelet/config.yaml`, reinicie e volte ao Ready. Corrija também o ConfigMap para não propagar o erro.

```bash
# LOCAL — selecione uma CSR Pending do nó que acabou de configurar
kubectl get csr
read -r -p 'Nome exato da CSR serving a inspecionar: ' CSR_NAME
kubectl get csr "$CSR_NAME" -o yaml
kubectl get csr "$CSR_NAME" -o jsonpath='{.spec.request}' | base64 -d | openssl req -text -noout
kubectl get nodes -o wide
```

Antes de aprovar, confira **todos** estes pontos:

| Campo | Resultado compatível com o pedido legítimo |
| --- | --- |
| `spec.signerName` | `kubernetes.io/kubelet-serving` |
| `spec.username` | `system:node:NOME_REAL` do nó recém-configurado |
| Subject do pedido | CN `system:node:NOME_REAL`, organização `system:nodes` |
| Subject Alternative Names | IP privado e nomes realmente pertencentes a esse nó, conferidos também pelo inventário/SSH |
| `spec.usages` | Uso de servidor: `server auth` e usos de chave compatíveis; não um pedido de client auth/admin |

Não confie no nome da CSR, que é aleatório, nem somente num SAN autodeclarado. Compare-o ao nó e ao inventário anterior. Se a identidade ou SAN não corresponder, deixe Pending e investigue; não aprove em lote. Para o único pedido conferido:

```bash
kubectl certificate approve "$CSR_NAME"
kubectl get csr "$CSR_NAME"
kubectl get csr "$CSR_NAME" -o jsonpath='{.status.certificate}' | base64 -d | openssl x509 -noout -subject -issuer -dates -ext subjectAltName
```

Espere Approved/Issued e o certificado emitido. Repita a inspeção individual para CP e cada worker. **HOST CP**, com o IP real de cada nó, valide a cadeia e o SAN no endpoint que Metrics Server usará:

```bash
read -r -p 'IP interno real do nó cuja CSR foi aprovada: ' KUBELET_IP
openssl s_client -connect "$KUBELET_IP:10250" -CAfile /etc/kubernetes/pki/ca.crt -verify_ip "$KUBELET_IP" -verify_return_error </dev/null
```

Espere `Verification: OK`/código de verificação 0. O teste verifica TLS, sem pedir dados protegidos do kubelet. Se o certificado ainda for o anterior, confira nos logs do nó a obtenção/rotação do serving certificate e aguarde a atualização; não remova a validação do cliente. A renovação futura também pode gerar CSRs pendentes: aprovação manual é aceitável para este laboratório, mas uma operação contínua precisa de monitoramento de validade e um aprovador com validação de identidade adequada.

## 6. Instalar Metrics Server e confirmar os dois caminhos TLS

Fixaremos **chart 3.13.0, Metrics Server 0.8.0**. A linha 0.8 suporta Kubernetes 1.31+, portanto cobre a base 1.35. Se já houver Metrics Server no cluster, confirme proprietário/versão com `helm list -A` antes de substituir; este procedimento é para o componente novo do laboratório.

Abra [metrics-values.yaml](../laboratorios/05-scheduling/metrics-values.yaml). `--kubelet-preferred-address-types=InternalIP` escolhe o endereço que você validou. `--kubelet-certificate-authority` aponta para a CA do cluster projetada no ServiceAccount. Para o caminho API Server → Metrics Server, `tls.type: helm` cria um certificado/Secret com nomes do Service e injeta a CA correspondente no APIService; `insecureSkipTLSVerify: false` exige validação. O chart também cria o RBAC necessário à coleta e à autenticação delegada.

```bash
helm repo add metrics-server https://kubernetes-sigs.github.io/metrics-server/
helm repo update
helm show chart metrics-server/metrics-server --version 3.13.0
helm template metrics-server metrics-server/metrics-server --namespace kube-system --version 3.13.0 --kube-version 1.35.0 -f laboratorios/05-scheduling/metrics-values.yaml > "$SCHED_DIR/metrics-renderizado.yaml"
helm upgrade --install metrics-server metrics-server/metrics-server --namespace kube-system --version 3.13.0 -f laboratorios/05-scheduling/metrics-values.yaml --wait --timeout 5m
kubectl -n kube-system rollout status deployment/metrics-server --timeout=180s
kubectl wait --for=condition=Available apiservice/v1beta1.metrics.k8s.io --timeout=180s
kubectl get apiservice v1beta1.metrics.k8s.io -o jsonpath='{.spec.insecureSkipTLSVerify}{"\n"}'
kubectl top nodes
kubectl -n curso-scheduling top pods
```

O arquivo renderizado inclui um Secret TLS gerado para revisão; guarde-o na área temporária privada, não no Git nem em evidências públicas. A instalação efetiva gerará seu próprio Secret. O certificado criado pelo chart tem validade de 365 dias; ele não recebe rotação automática só porque Helm o gerou. Registre a validade e planeje sua substituição antes do vencimento, ou adote uma solução de emissão/renovação em uma etapa futura.

Espere APIService Available, valor `false` e números no top após os primeiros ciclos. Se falhar, `kubectl describe apiservice v1beta1.metrics.k8s.io` localiza problemas no primeiro caminho; `kubectl logs -n kube-system deployment/metrics-server --tail=100` revela erros ao coletar kubelets. `x509` aponta certificado/cadeia/SAN, timeout aponta caminho de rede, conexão recusada aponta listener indisponível. A solução final desta aula não usa `--kubelet-insecure-tls` nem desabilita validação no APIService.

## 7. HPA e carga limitada

O [hpa.yaml](../laboratorios/05-scheduling/hpa.yaml) seleciona `Deployment/agenda`, mínimo 2, máximo 4 e utilização alvo de CPU 50%. A janela de estabilização da redução é 180 segundos, evitando reduzir imediatamente numa queda breve de carga. É esperado levar vários ciclos para observar subida e alguns minutos para descida.

```bash
kubectl apply -f laboratorios/05-scheduling/hpa.yaml
kubectl -n curso-scheduling get hpa agenda -w
# Outro terminal LOCAL:
kubectl -n curso-scheduling get pods -l app=agenda
read -r -p 'Nome de uma réplica agenda pronta: ' LOAD_POD
kubectl -n curso-scheduling exec "$LOAD_POD" -- timeout 120 sh -c 'while :; do :; done'
```

O laço roda dentro do cgroup de uma réplica e termina em 120 segundos; o status não zero de timeout é esperado. Ele testa a resposta à CPU, não a capacidade HTTP do servidor. Observe `kubectl top pods -n curso-scheduling`, `kubectl describe hpa agenda -n curso-scheduling` e `kubectl get deployment agenda -n curso-scheduling`. Registre, a cada 30 segundos, horário, utilização, réplicas desejadas/prontas e evento de scale. Não atribua falta de escala apenas a CPU: métricas ausentes, readiness e limite máximo também contam.

Após a carga parar, aguarde a queda do consumo e da recomendação até o mínimo. Enquanto o HPA controla as réplicas, não reaplique o campo `replicas` da base, pois outro cliente pode disputar essa configuração. Para voltar ao estado sem autoscaling: `kubectl delete hpa agenda -n curso-scheduling`, `kubectl apply -f laboratorios/05-scheduling/base.yaml` e `kubectl rollout status deployment/agenda -n curso-scheduling --timeout=180s`.

## Desafio independente

Em uma cópia da base, implemente três réplicas que prefiram hostnames distintos, mantenham pelo menos duas disponíveis durante eviction e peçam 50m. Use os mesmos mecanismos praticados: topology spread, PDB e HPA. Configure mínimo 3, máximo 5 e alvo 60%; demonstre subida e descida com carga limitada. Com apenas dois workers, explique por que distribuição perfeita em três nós é impossível e o que mudaria se a separação fosse obrigatória.

Entregue os eventos dos dois Pending, matriz nó/Pod antes/depois, PDB negando e permitindo eviction, cadeia/SANs verificados sem chaves privadas e uma tabela de réplicas por tempo. A pesquisa permitida é delimitada: `kubectl explain deployment.spec.template.spec.affinity` para confirmar o campo de afinidade e `kubectl explain hpa.spec.behavior` para localizar a janela de redução. Termine a consulta quando conseguir apontar o campo usado, sem precisar estudar o site inteiro.

## Fechamento

Explique: por que top baixo não garante espaço para scheduling? Por que toleration não obriga usar um nó? O que PDB protege e o que não protege? Qual a diferença entre certificado cliente e serving do kubelet? Quem cria Pods e quem criaria EC2 ao escalar?

**Rubrica, 10 pontos:** requests versus uso (2); seletor/toleration/affinity/spread explicados e restaurados (2); drain/PDB com recuperação do nó (3); HPA com TLS válido e evidência de subida/descida (3). Avance com 8/10, sem bypass do PDB nem TLS inseguro como estado final.

Confira `kubectl get nodes` e `kubectl describe node "$WORKER_1"`/`"$WORKER_2"`: todos devem estar schedulable como antes, sem os taints/labels que você adicionou. Se interrompeu um drain, use uncordon no nó exato. Após guardar as evidências, remova somente `curso-scheduling` com `kubectl delete namespace curso-scheduling`. Preserve Metrics Server e os serving certificates assinados para os próximos módulos. Para encerrá-lo ao final de toda a trilha, use `helm uninstall metrics-server -n kube-system`; os kubelets podem continuar com certificados assinados.

Não publique o render Helm com Secret nem CSRs/certificados acompanhados de suas chaves. Guarde backups de configuração e validade até conferir a recuperação; renovação continuada e node autoscaler permanecem trabalho posterior, claramente distintos do resultado demonstrado aqui. Próximo: [06 — Segurança](06-seguranca.md).

## Referências opcionais

Fontes verificadas em **12/09/2026**; complementam mecanismos já apresentados acima.

- [Scheduler](https://kubernetes.io/docs/concepts/scheduling-eviction/kube-scheduler/) e [node affinity](https://kubernetes.io/docs/concepts/scheduling-eviction/assign-pod-node/) detalham filtragem, pontuação e expressões.
- [Taints](https://kubernetes.io/docs/concepts/scheduling-eviction/taint-and-toleration/) e [topology spread](https://kubernetes.io/docs/concepts/scheduling-eviction/topology-spread-constraints/) aprofundam efeitos e domínios elegíveis.
- [Drain](https://kubernetes.io/docs/tasks/administer-cluster/safely-drain-node/) e [PDB](https://kubernetes.io/docs/tasks/run-application/configure-pdb/) cobrem manutenção completa e orçamentos de interrupção.
- [Serving certificates com kubeadm](https://kubernetes.io/docs/tasks/administer-cluster/kubeadm/kubeadm-certs/#enabling-signed-kubelet-serving-certificates) e [TLS bootstrap](https://kubernetes.io/docs/reference/access-authn-authz/kubelet-tls-bootstrapping/) detalham signers, aprovação e renovação.
- [Metrics Server 0.8.0](https://github.com/kubernetes-sigs/metrics-server/tree/v0.8.0) e [chart 3.13.0](https://github.com/kubernetes-sigs/metrics-server/tree/metrics-server-helm-chart-3.13.0/charts/metrics-server) registram compatibilidade, argumentos e geração de TLS.
- [HPA](https://kubernetes.io/docs/tasks/run-application/horizontal-pod-autoscale/) aprofunda a fórmula, métricas ausentes e estabilização.
