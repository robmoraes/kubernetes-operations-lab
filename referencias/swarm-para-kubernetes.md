# Pontes com o Swarm

As equivalências são aproximadas. O Kubernetes divide responsabilidades que no Swarm aparecem juntas, e isso muda a investigação de incidentes.

| Experiência no Swarm | Conceito a aprender | Diferença operacional |
|---|---|---|
| Service com réplicas | Deployment → ReplicaSet → Pods | O objeto Service do Kubernetes é rede, não um processo |
| Estado desejado e reconciliação | Controllers e API declarativa | Conceito familiar; diversos controllers reconciliam recursos relacionados |
| Stack / Compose | Manifests, Kustomize, Helm release | Namespace organiza/isola escopo; não equivale sozinho a uma stack |
| Manager e consenso Raft | API Server, controllers, scheduler, etcd | etcd é o armazenamento com consenso; componentes têm funções separadas |
| Overlay network | CNI e dataplane de Services | Política de rede depende do plugin; não aparece só por criar um namespace |
| Routing mesh | Service, implementação do dataplane e entrada externa | NodePort/LoadBalancer/Ingress têm responsabilidades distintas |
| Labels de Traefik | Ingress ou Gateway/HTTPRoute | Um controller transforma esses objetos em configuração de proxy |
| Constraints | nodeSelector, affinity, taints/tolerations | Tolerar um taint permite, mas não obriga agendamento naquele nó |
| Restart policy / healthcheck | RestartPolicy, probes e controllers | Readiness controla tráfego; liveness reinicia container; Deployment repõe Pods |
| Volumes | PVC, PV, StorageClass, CSI | Persistência não implica replicação entre zonas nem backup |
| Secrets / configs | Secret / ConfigMap | Base64 não cifra dados; RBAC e criptografia em repouso são decisões separadas |
| Update / rollback | RollingUpdate e histórico de ReplicaSets | Banco e dados não são revertidos automaticamente junto com o Deployment |

## Percurso mental de uma falha

Se um Pod não nasce, examine admissão, quotas, scheduler e montagem de volume. Se nasce e reinicia, examine processo, probes, memória e dependências. Se está Ready e não recebe tráfego, examine selectors, EndpointSlices, portas, políticas, DNS e proxy de entrada. A API descreve intenção e estado observado; nem sempre o campo `spec` desejado já se tornou realidade.

## Três correções úteis para esta trilha

**CRD não é uma stack executável.** Ela registra um tipo na API. Um custom resource é um objeto desse tipo. A automação vem de um controller que o observa. Helm pode instalar CRDs, mas não substitui a reconciliação de um operator.

**RWO significa um nó, não necessariamente um Pod.** Vários Pods no mesmo nó podem acessar um volume ReadWriteOnce. Use a arquitetura correta de escrita e, quando suportado pelo CSI, ReadWriteOncePod se precisar de exclusividade por Pod.

**Rancher não precisa de RDS como banco de aplicação.** Sua instalação Kubernetes mantém estado em recursos do cluster/etcd. A sugestão anterior de “RDS para Rancher” não se aplica desse modo; siga o backup específico do Rancher se estudá-lo depois. RDS é uma opção para aplicações que usam um banco relacional externo.

Referências: [arquitetura](https://kubernetes.io/docs/concepts/architecture/), [controllers](https://kubernetes.io/docs/concepts/architecture/controller/), [volumes persistentes](https://kubernetes.io/docs/concepts/storage/persistent-volumes/), [backup do Rancher](https://ranchermanager.docs.rancher.com/how-to-guides/new-user-guides/backup-restore-and-disaster-recovery).
