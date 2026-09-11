# 05 — Agendamento, capacidade e disponibilidade

Reserve **14–18 horas**. Precisa de dois workers Ready, CNI funcionando e compreensão de requests/limits. Trabalhe na estação, com o contexto do cluster descartável, a partir da raiz do repo. Os exemplos criam `curso-scheduling`; substitua `worker-1` e `worker-2` pelos nomes reais.

Você irá provar por que um pod está Pending, controlar sua colocação, drenar um nó respeitando disponibilidade e observar um HPA. Esses são problemas operacionais frequentes, inclusive quando CPU aparentemente está ociosa.

## A decisão do scheduler

O scheduler procura nós elegíveis para pods ainda sem `spec.nodeName`: recursos **solicitados**, taints, seletores, afinidades, restrições de topologia e volumes participam da decisão. Depois pontua candidatos. `kubectl top` mostra uso; `describe node` mostra recursos já solicitados. Um nó com pouco uso pode não ter requests livres. Limits restringem execução: CPU pode sofrer throttling e excesso de memória pode causar OOM.

| Ferramenta | Efeito | Armadilha |
|---|---|---|
| `nodeSelector` / affinity required | Exige labels no nó | Label inexistente deixa Pending |
| affinity preferred | Preferência, não exigência | Não garante isolamento |
| taint / toleration | Nó repele / pod tolera | Toleration não obriga usar o nó |
| pod anti-affinity | Separa pods selecionados | Regra obrigatória pode impedir mais réplicas |
| topology spread | Controla desequilíbrio por domínio | Só faz sentido com labels/topologia reais |
| PDB | Limita interrupções voluntárias via eviction | Não impede pane de EC2 ou `delete pod` |

`IgnoredDuringExecution` significa que uma mudança posterior na label não expulsa automaticamente o pod já agendado. `NoSchedule` afeta novas colocações; `NoExecute` também pode expulsar existentes. Não use `spec.nodeName` como solução padrão: ele pula a seleção normal do scheduler. [Agendamento por nó](https://kubernetes.io/docs/concepts/scheduling-eviction/assign-pod-node/).

## Laboratório A — Requests e restrições

```bash
kubectl config current-context
kubectl get nodes -L kubernetes.io/hostname,topology.kubernetes.io/zone
kubectl describe node worker-1
kubectl apply -f laboratorios/05-scheduling/base.yaml
kubectl -n curso-scheduling rollout status deploy/agenda --timeout=120s
kubectl -n curso-scheduling get pods -o wide
```

Há duas réplicas, requests explícitos e preferência por distribuir entre hostnames. `ScheduleAnyway` permite concentrar pods quando só restar um worker; a decisão pode degradar resiliência para manter capacidade. O manifesto não finge três zonas em um cluster de uma AZ.

Agora provoque um Pending sem consumir memória real:

```bash
kubectl -n curso-scheduling set resources deployment/agenda \
  --requests=cpu=100,memory=256Mi --limits=cpu=100,memory=512Mi
kubectl -n curso-scheduling get pods
kubectl -n curso-scheduling describe pod NOME_DO_POD_PENDING
kubectl -n curso-scheduling get events --sort-by=.metadata.creationTimestamp
```

O número `100` representa cem CPUs, não 100 millicores. Identifique `Insufficient cpu`. O rollout pode manter pods antigos saudáveis: confira ReplicaSets, `maxSurge` e `maxUnavailable`. Recupere reaplicando `base.yaml`, aguarde rollout e documente a distinção entre admissão, scheduling e execução.

Teste uma label impossível:

```bash
kubectl -n curso-scheduling patch deployment agenda --type=merge \
  -p '{"spec":{"template":{"spec":{"nodeSelector":{"curso.pool":"inexistente"}}}}}'
kubectl -n curso-scheduling get pods -o wide
kubectl -n curso-scheduling describe pod NOME_DO_POD_PENDING
kubectl -n curso-scheduling patch deployment agenda --type=merge \
  -p '{"spec":{"template":{"spec":{"nodeSelector":null}}}}'
kubectl -n curso-scheduling rollout status deploy/agenda
```

Não aumente instâncias até distinguir falta de capacidade de uma regra impossível. Registre o evento que comprova a causa.

## Laboratório B — Taints e drain

Liste workloads do worker antes de alterações: `kubectl get pods -A -o wide --field-selector spec.nodeName=worker-1`. Taints de laboratório são mudanças no nó e podem afetar outros módulos. Não aplique em nó de produção ou no único nó compatível com um volume ativo.

```bash
kubectl taint node worker-1 curso=manutencao:NoSchedule
kubectl -n curso-scheduling rollout restart deploy/agenda
kubectl -n curso-scheduling rollout status deploy/agenda --timeout=120s
kubectl -n curso-scheduling get pods -o wide
kubectl taint node worker-1 curso=manutencao:NoSchedule-
```

Com capacidade disponível, as novas réplicas ficam em worker-2. Como desafio guiado, adicione uma toleration específica e affinity obrigatória para worker-1 em uma cópia do manifesto; explique por que precisa das duas para reservar colocação. Restaure a base antes do próximo teste.

Crie um PDB de bloqueio didático:

```bash
kubectl apply -f laboratorios/05-scheduling/pdb-bloqueio.yaml
kubectl -n curso-scheduling get pdb
kubectl -n curso-scheduling get pods -o wide
# Escolha um worker que realmente hospeda agenda.
kubectl drain worker-1 --ignore-daemonsets --pod-selector app=agenda --timeout=45s
```

Esse drain é **parcial**, seleciona só pods `app=agenda` e cordona o nó. Não conclui a manutenção real da máquina. Com duas réplicas saudáveis e `minAvailable: 2`, `ALLOWED DISRUPTIONS` é zero e a eviction é negada. O timeout é esperado. Não use `--disable-eviction` ou `--force` para esconder o problema.

```bash
kubectl -n curso-scheduling patch pdb agenda --type=merge -p '{"spec":{"minAvailable":1}}'
kubectl drain worker-1 --ignore-daemonsets --pod-selector app=agenda --timeout=120s
kubectl -n curso-scheduling get pods -o wide
kubectl uncordon worker-1
```

Confirme o serviço saudável e o novo pod antes de concluir. Na operação real, primeiro valide todos os pods/PDBs/volumes, reserve capacidade de destino e execute drain **sem** seletor. `emptyDir` pede decisão explícita sobre perda de dados (`--delete-emptydir-data`); não adicione essa flag indiscriminadamente. Uncordon permite agendamento futuro, não rebalanceia automaticamente os pods. [Drain seguro](https://kubernetes.io/docs/tasks/administer-cluster/safely-drain-node/), [PDB](https://kubernetes.io/docs/tasks/run-application/configure-pdb/).

## Laboratório C — Metrics Server e HPA

HPA de CPU usa a relação consumo/request, então request ausente impede calcular a utilização esperada. Ele muda réplicas; não cria EC2. Node autoscaler trata capacidade de nós; em kubeadm não aparece automaticamente. Metrics Server oferece dados recentes para autoscaling, não histórico de observabilidade.

Na estação, adicione `helm repo add metrics-server https://kubernetes-sigs.github.io/metrics-server/`, rode `helm repo update` e consulte `helm search repo metrics-server/metrics-server --versions`. Escolha uma versão compatível com 1.35 e registre-a. O control plane precisa alcançar Metrics Server, e ele precisa alcançar kubelets em TCP 10250; confira security groups e rede de pods.

**Resolva TLS antes:** em kubeadm os certificados serving dos kubelets podem ser autoassinados. Configure `serverTLSBootstrap: true` no ConfigMap `kube-system/kubelet-config` e em `/var/lib/kubelet/config.yaml` de cada nó, reiniciando kubelet um por vez. Leia [serving certificates](https://kubernetes.io/docs/tasks/administer-cluster/kubeadm/kubeadm-certs/#enabling-signed-kubelet-serving-certificates). Veja os CSRs com `kubectl get csr`, inspecione cada requisição com `kubectl get csr NOME -o jsonpath='{.spec.request}' | base64 -d | openssl req -text -noout` e compare requester, CN e SANs ao inventário do nó. Só então `kubectl certificate approve NOME`. Nunca aprove todos automaticamente.

```bash
helm upgrade --install metrics-server metrics-server/metrics-server \
  --namespace kube-system --version VERSAO_CHART
kubectl -n kube-system rollout status deploy/metrics-server --timeout=180s
kubectl get apiservice v1beta1.metrics.k8s.io
kubectl top nodes
kubectl -n curso-scheduling top pods
```

`Available=True` e valores numéricos devem aparecer após os primeiros ciclos. Se falhar, `kubectl -n kube-system logs deploy/metrics-server` diferencia certificado, timeout e conexão recusada. `--kubelet-insecure-tls` serve apenas como diagnóstico temporário em cluster descartável; registrar que remove validação de identidade é obrigatório se o utilizar. Não é a configuração final deste curso. [Requisitos do Metrics Server](https://github.com/kubernetes-sigs/metrics-server#requirements).

```bash
kubectl apply -f laboratorios/05-scheduling/hpa.yaml
kubectl -n curso-scheduling get hpa agenda -w
# Em outro terminal, escolha uma réplica existente:
kubectl -n curso-scheduling get pods -l app=agenda
kubectl -n curso-scheduling exec NOME_DO_POD -- \
  timeout 120 sh -c 'while :; do :; done'
```

O gerador consome CPU dentro de uma réplica, limitado pelo cgroup e por 120 segundos; código de saída de timeout é esperado. Observe consumo, target e aumento de réplicas até o teto 4. Nem todo ciclo escala: média entre réplicas, readiness e janelas de estabilização contam. Após parar a carga, aguarde vários minutos para redução. Não reaplique `replicas` da base enquanto HPA controla o Deployment; isso cria disputa de configuração. Para retornar à etapa sem autoscaling, exclua apenas `hpa/agenda` e reaplique a base.

## Desafio e rubrica

Sem copiar a aula, implante três réplicas que prefiram nós distintos, preservem pelo menos duas durante eviction e tenham request de 50m. Explique quantas cabem se um worker cair e qual comportamento mudaria com anti-affinity obrigatória. Faça um HPA com mínimo 3, máximo 5 e alvo 60%, com uma prova de subida e descida. [Algoritmo e comportamento do HPA](https://kubernetes.io/docs/tasks/run-application/horizontal-pod-autoscale/).

Entregue eventos dos dois Pending, matriz nó/pod antes/depois, PDB impedindo e permitindo eviction, métricas e gráfico simples anotado de réplicas por tempo. Rubrica: requests versus uso (2), scheduling explicado (2), drain/PDB com restauração de taints e cordon (3), HPA com TLS válido e evidência (3). Aprovação: 8/10, sem bypass do PDB. Confira no fim `kubectl get nodes`, `kubectl describe node` e retire apenas labels/taints que você adicionou. O namespace pode ser removido após guardar as evidências; Metrics Server será útil nos próximos módulos.

Fontes consultadas em 10/09/2026: [scheduler](https://kubernetes.io/docs/concepts/scheduling-eviction/kube-scheduler/), [taints](https://kubernetes.io/docs/concepts/scheduling-eviction/taint-and-toleration/), [topology spread](https://kubernetes.io/docs/concepts/scheduling-eviction/topology-spread-constraints/), além das referências nos exercícios. Abra a versão 1.35 na documentação quando comparar campos.
