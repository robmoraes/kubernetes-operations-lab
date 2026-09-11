# Laboratórios

Execute comandos a partir da raiz do repositório e no contexto indicado no capítulo. Os diretórios contêm manifests prontos, configurações de ferramentas e alternativas que exigem edição. **Não aplique esta árvore inteira com `kubectl apply -R`.**

| Pasta | Uso |
|---|---|
| [02-workloads](02-workloads/) | Aplicação-base e workloads de batch |
| [03-rede](03-rede/) | Traefik, diagnóstico, Ingress e Gateway API |
| [04-storage](04-storage/) | Escolher PV estático EBS, local ou provisionamento dinâmico; revisar placeholders/IAM |
| [05-scheduling](05-scheduling/) | Distribuição, PDB e HPA |
| [06-seguranca](06-seguranca/) | Aplicar base/RBAC e políticas na sequência da aula |
| [07-troubleshooting](07-troubleshooting/) | Carga isolada e defeitos intencionais |
| [09-entrega](09-entrega/) | Chart, overlays e Application Argo CD |
| [10-alta-disponibilidade](10-alta-disponibilidade/) | Exemplo de balanceador e plano de falhas |
| [11-eks](11-eks/) | Terraform e storage do EKS; configurações devem ser preenchidas |
| [12-sre](12-sre/) | Métricas, SLO e postmortem |

Os módulos 01 e 08 ensinam operações de host diretamente nas aulas. Não há um script que instala todo o curso ou restaura etcd automaticamente.

Para verificar um exemplo, siga os comandos de renderização/dry-run da aula e depois os testes funcionais. Arquivos `values`, configs Prometheus, exemplos IAM e templates Helm não são objetos Kubernetes para `kubectl apply` direto.

Alguns exemplos criam recursos globais (StorageClass, PV, CRD, ClusterRole, CSI) além dos namespaces. Revise o escopo e a limpeza do capítulo. EBS/PVC com Retain, snapshots e recursos criados por controllers podem continuar existindo depois de remover a aplicação.
