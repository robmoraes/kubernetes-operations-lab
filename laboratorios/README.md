# Laboratórios

Execute comandos a partir da raiz do repositório e no contexto indicado no capítulo. Os diretórios contêm manifests prontos, configurações de ferramentas e alternativas que exigem edição. **Não aplique esta árvore inteira com `kubectl apply -R`.**

| Pasta | Uso |
|---|---|
| [01-control-plane](01-control-plane/) | Teste HTTP/DNS e Terraform de reconstrução, usado somente após a primeira execução manual |
| [02-workloads](02-workloads/) | Aplicação-base, Job/CronJob e DaemonSet didático |
| [03-rede](03-rede/) | Traefik, diagnóstico, Ingress e Gateway API |
| [04-storage](04-storage/) | Escolher PV estático EBS, local ou provisionamento dinâmico; revisar placeholders/IAM |
| [05-scheduling](05-scheduling/) | Distribuição, PDB e HPA |
| [06-seguranca](06-seguranca/) | Aplicar base/RBAC e políticas na sequência da aula |
| [07-troubleshooting](07-troubleshooting/) | Carga isolada e defeitos intencionais |
| [08-manutencao](08-manutencao/) | Marcador e registro de backup/restore no cluster auxiliar descartável |
| [09-entrega](09-entrega/) | Chart, overlays e Application Argo CD |
| [10-alta-disponibilidade](10-alta-disponibilidade/) | Exemplo de balanceador e plano de falhas |
| [11-eks](11-eks/) | Terraform e storage do EKS; configurações devem ser preenchidas |
| [12-sre](12-sre/) | Métricas, SLO e postmortem |

Os módulos 01 e 08 ensinam operações de host diretamente nas aulas. O primeiro cluster do módulo 01 é criado e destruído manualmente; só depois seu Terraform pode reconstruir a base para novas sessões. Não há um script que instala todo o curso ou restaura etcd automaticamente. Os capítulos são o roteiro completo: este índice apenas localiza os materiais.

Para verificar um exemplo, siga os comandos de renderização/dry-run da aula e depois os testes funcionais. Arquivos `values`, configs Prometheus, exemplos IAM e templates Helm não são objetos Kubernetes para `kubectl apply` direto.

Alguns exemplos criam recursos globais (StorageClass, PV, CRD, ClusterRole, CSI) além dos namespaces. Revise o escopo e a limpeza do capítulo. EBS/PVC com Retain, snapshots e recursos criados por controllers podem continuar existindo depois de remover a aplicação.
