# 11 — EKS, Terraform e responsabilidades na AWS

**Tempo sugerido:** 20–24 horas. **Pré-requisitos:** módulos 01–10; conta AWS de estudos,
AWS CLI v2, Terraform >= 1.6, IAM role administrativa e orçamento para a janela.
O Terraform entregue é um laboratório executável; nada é provisionado ao ler este curso.
Você pode estudar e validar os arquivos sem fazer `apply`.

## Quem opera cada parte

| Responsabilidade | kubeadm em EC2 | EKS deste módulo |
|---|---|---|
| API/etcd e substituição de CP | você | AWS opera o control plane |
| Atualização da minor | kubeadm e operação sua | você planeja/solicita no EKS |
| Workers, capacidade e AMIs | você | node group gerenciado, decisões suas |
| Aplicação, RBAC, SLO e recuperação de dados | você | você |
| Rede, IAM, exposição e custos | você | você |

EKS não oferece SSH ao etcd gerenciado nem usa seu script kubeadm. O trabalho aprendido
continua útil para diagnosticar a fronteira entre aplicação, nó, rede e control plane.
O exercício usa EKS convencional com Managed Node Groups; EKS Auto Mode tem outras
responsabilidades, provisionadores de storage e custos, portanto é uma comparação posterior.

## Leia a infraestrutura antes de criá-la

[`laboratorios/11-eks`](../laboratorios/11-eks/) contém uma VPC `10.80.0.0/16`, três subnets
públicas e três privadas, Internet Gateway, um NAT Gateway com EIP, EKS, três workers
ARM64 AL2023, roles IAM, access entry, add-ons e retenção de logs por sete dias.
Verifique conflito de CIDR antes de interligar essa VPC à sua rede.

Nós privados saem pelo NAT para registros e APIs AWS. O endpoint Kubernetes é privado
para nós e público apenas para seu IPv4 `/32`. Se seu IP mudar, atualize o Terraform.
Uma única saída NAT é simplificação didática: perder sua AZ afeta saída das outras AZs
e pode gerar tráfego entre zonas. O desafio final pede um desenho de saída resiliente.

Antes do `plan`, estime custo para a região e as horas de laboratório: control plane
EKS, três EC2s, discos, NAT por hora/dados, IPv4 público do NAT, logs e tráfego entre
zonas. Adicione depois EBS de PVC, snapshots e balanceadores. Parar os workers não
elimina cobrança do cluster, NAT e volumes. Configure um orçamento/alerta AWS e registre
a estimativa no portfólio; os preços precisam ser consultados na data de execução.

## Laboratório A — Identidade, região e versões

Use credenciais temporárias por IAM Identity Center/assume-role. Não coloque access keys
nos arquivos Terraform. A identidade que provisiona precisa criar os recursos do exercício
e passar as roles necessárias; a role do acesso kubectl é configurada explicitamente.

```bash
aws sts get-caller-identity
aws configure get region
aws ec2 describe-availability-zones --region us-east-1 \
  --query 'AvailabilityZones[?State==`available`].[ZoneName,ZoneId]' --output table
aws eks describe-cluster-versions --region us-east-1 --output table
```

Troque região nos comandos e tfvars consistentemente. Escolha três AZs permitidas pelo
EKS; os nomes `1a/1b/1c` variam entre contas e nem todo ZoneId é suportado. Consulte
os requisitos de subnets antes de preencher. Confirme disponibilidade de `t4g.medium`
e quotas EC2/EKS/VPC/NAT. AL2023 aqui é AMI otimizada EKS ARM64.

Copie `terraform.tfvars.example` para `terraform.tfvars` e edite todos os placeholders.
`admin_principal_arn` deve ser ARN IAM de uma role, não o ARN STS da sessão retornada
por `get-caller-identity`. Use a mesma role ao executar `update-kubeconfig`.

Consulte versões compatíveis; não substitua por `latest`:

```bash
for addon in vpc-cni coredns kube-proxy eks-pod-identity-agent aws-ebs-csi-driver; do
  aws eks describe-addon-versions --region us-east-1 \
    --kubernetes-version 1.35 --addon-name "$addon" \
    --query 'addons[].addonVersions[].[addonVersion,architecture,compatibilities]' \
    --output json
done
```

Escolha versões que incluam ARM64 e a versão do cluster; registre-as em `addon_versions`.
Leia release notes ao sair da versão padrão. Revalide minor e add-ons se executar o
curso no futuro. O lockfile fixa o provider Terraform, não versões dos add-ons.

## Laboratório B — Planejar e provisionar

```bash
cd laboratorios/11-eks
terraform init
terraform fmt -check
terraform validate
terraform plan -out=lab.tfplan
terraform show lab.tfplan
```

Leia cada recurso e confirme conta, região, CIDRs, principal administrativo, três EC2s
e o NAT. `init`/`validate` não criam infraestrutura; `plan` consulta AWS e gera estado
planejado. O próximo comando cria recursos cobrados e só deve ser executado na janela
de laboratório prevista:

```bash
terraform apply lab.tfplan
aws eks update-kubeconfig --name curso-eks --region us-east-1 --alias curso-eks
kubectl config current-context
kubectl get nodes -L topology.kubernetes.io/zone,kubernetes.io/arch
kubectl -n kube-system get pods
aws eks list-addons --cluster-name curso-eks --region us-east-1
```

Use os outputs se mudou o nome/região. Armazene state e planos fora de repositórios
públicos; eles podem conter dados sensíveis. Versione `.terraform.lock.hcl`. Em equipe,
use backend remoto com criptografia, versionamento, controle de acesso e bloqueio.
Crie o backend separadamente para não depender do próprio state que ele guarda.

Se um add-on falhar, consulte `aws eks describe-addon` e eventos antes de executar
novo `apply`. Falha de criação não significa ausência de recursos ou de cobrança.
Não use `terraform destroy` como primeira técnica de diagnóstico.

## Laboratório C — Separar as duas direções de autorização

Access entry responde “esta pessoa/role pode acessar a API Kubernetes?”. Pod Identity
responde “este ServiceAccount pode chamar APIs AWS?”. RBAC continua governando ações
dos workloads na API Kubernetes. São fronteiras distintas de segurança.

```bash
aws eks list-access-entries --cluster-name curso-eks --region us-east-1
aws eks list-pod-identity-associations --cluster-name curso-eks --region us-east-1
kubectl auth can-i create deployments -n curso
kubectl -n kube-system get daemonset eks-pod-identity-agent
kubectl -n kube-system get serviceaccount ebs-csi-controller-sa
```

O Terraform associa a role EBS somente a `kube-system/ebs-csi-controller-sa`. A trust
policy confia no serviço EKS Pod Identity; o agent entrega credenciais temporárias ao
pod. O SDK deve suportar esse provedor e usar a cadeia padrão de credenciais.

A policy AWS gerenciada EBS acompanha a recomendação atual consultada; revise os
privilégios antes de produção. A role dos nós recebe CNI no primeiro laboratório para
simplificar bootstrap. Como desafio, migre VPC CNI para identidade própria e restrinja
IMDS, validando DNS, pull de imagens e pods novos antes de retirar a permissão antiga.

## Rede e entrada de tráfego

O Calico do cluster manual fornecia a rede de pods. Aqui Amazon VPC CNI atribui IPs da
VPC: disponibilidade de IPs, ENIs e limites por instância entram no planejamento.
Não aplique o manifest de instalação Calico do kubeadm por cima desse CNI. NetworkPolicy
precisa de suporte e configuração do mecanismo escolhido; existir na API não prova enforcement.

Reinstale a aplicação do módulo 02 no contexto `curso-eks`. Teste primeiro com
`kubectl port-forward -n curso service/web 8080:80`. Traefik pode continuar como proxy
L7; para publicar externamente com NLB, instale/configure AWS Load Balancer Controller,
sua role IAM e um Service LoadBalancer do Traefik com a classe/anotações documentadas.
Um ALB pode rotear diretamente para serviços por esse controller. Especifique a classe
para que Traefik e ALB não tentem reconciliar o mesmo objeto de entrada.

O Terraform não instala um ingress nem cria LB de aplicação. Faça esta extensão como
exercício: instale o controller pela documentação oficial, fixe a versão, publique
Traefik pelo NLB, prove HTTPS e registre ARN, tags e procedimento de limpeza.

## Laboratório D — EBS e uma falha reversível

Volte à raiz do repositório e aplique somente no EKS de estudo:

```bash
cd ../..
kubectl apply -f laboratorios/11-eks/storage.yaml
kubectl -n curso-eks-storage wait --for=condition=Ready pod/leitor --timeout=3m
kubectl -n curso-eks-storage exec leitor -- sh -c 'date -Iseconds > /dados/prova.txt'
kubectl -n curso-eks-storage get pvc
kubectl -n curso-eks-storage delete pod leitor
kubectl apply -f laboratorios/11-eks/storage.yaml
kubectl -n curso-eks-storage wait --for=condition=Ready pod/leitor --timeout=3m
kubectl -n curso-eks-storage exec leitor -- cat /dados/prova.txt
```

O conteúdo deve persistir. O provisionador é `ebs.csi.aws.com`; Auto Mode usa outro.
`UnauthorizedOperation` aponta para identidade/policy do driver; `Pending` também pode
indicar falta de nós na AZ, permissões KMS, attach ou configuração do CSI. Recolha eventos.
O exercício cria Pod simples de propósito: ele não se recria sozinho até reaplicar YAML.

## Autoscaling e operação

Managed Node Group não implica autoscaling orientado a pods automaticamente. HPA muda
réplicas; Cluster Autoscaler muda capacidade de grupos; Karpenter provisiona nós a partir
das necessidades dos pods e de `NodePool`/`EC2NodeClass`. Escolha uma gestão coerente
por grupo, limites de custo e capacidade base para controllers. Não instale dois
controladores concorrentes para gerenciar a mesma capacidade.

Desafio: reproduza um Pending por falta de CPU, implante Karpenter conforme guia oficial
em extensão separada e prove criação/remoção de nó. Compare requests, quotas, tipos ARM,
Spot/interrupções, disruption budgets e concentração por AZ antes de chamar isso de HA.

## Encerrar o laboratório e comprovar a limpeza

Antes de destruir EKS, remova Ingress/Services LoadBalancer que criou e aguarde a remoção
dos LBs pelo controller. Registre ID do EBS do PV, decida se haverá snapshot e remova
o pod/PVC deste exercício. `Retain` deixa volume e PV para tratamento manual.

```bash
kubectl get pv -o custom-columns=PV:.metadata.name,CLAIM:.spec.claimRef.name,VOLUME:.spec.csi.volumeHandle
kubectl delete -f laboratorios/11-eks/storage.yaml
cd laboratorios/11-eks
terraform plan -destroy -out=destruir.tfplan
terraform show destruir.tfplan
terraform apply destruir.tfplan
terraform state list
```

Revise o plano antes da última ação: ela exclui a infraestrutura dedicada do laboratório.
Volumes de PVC, snapshots e LBs criados por controllers não estão necessariamente no
state. No console, filtre pelos IDs/tags registrados, confirme ausência de anexos e
exclua somente os discos de exercício sem dados a preservar. Confira também EIPs,
NAT, logs, ENIs e balanceadores. Não apague recursos por um filtro amplo de nome.

Gate: explique IAM versus RBAC, reproduza o cluster por Terraform, prove PVC e acesso
restrito, apresente custo previsto/observado e inventário de limpeza. Em preparação
para CKA, separe competências Kubernetes portáveis de detalhes específicos da AWS.

## Fontes primárias consultadas em 2026-09-10

- [Provider AWS: EKS](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/eks_cluster).
- [EKS: rede](https://docs.aws.amazon.com/eks/latest/userguide/network-reqs.html) e [VPC CNI](https://docs.aws.amazon.com/eks/latest/userguide/managing-vpc-cni.html).
- [Access entries](https://docs.aws.amazon.com/eks/latest/userguide/access-entries.html) e [Pod Identity](https://docs.aws.amazon.com/eks/latest/userguide/pod-identities.html).
- [EBS CSI](https://docs.aws.amazon.com/eks/latest/userguide/ebs-csi.html).
- [AWS Load Balancer Controller](https://kubernetes-sigs.github.io/aws-load-balancer-controller/latest/).
- [Karpenter](https://karpenter.sh/docs/concepts/) e [preços EKS](https://aws.amazon.com/eks/pricing/).
