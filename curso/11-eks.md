# 11 — EKS, Terraform e responsabilidades na AWS

## Antes de começar

Reserve **24–32 horas**. Conclua [rede/Helm/TLS](03-rede.md), o preparo **AWS CLI v2,
jq e SSO** de [storage](04-storage.md), [scheduling](05-scheduling.md), [segurança](06-seguranca.md)
e [entrega](09-entrega.md). HA do módulo 10 fornece a comparação operacional.
Use uma estação Ubuntu 24.04 amd64 ou arm64, kubectl, Helm e acesso à internet.
A instalação Terraform é ensinada abaixo. A região guiada é `us-east-1`; adaptar
região exige ajustar AZs, quotas, versões disponíveis e todos os comandos de modo coerente.

Tenha uma conta **sandbox**, acesso federado IAM Identity Center já concedido e uma
role cujo permission set possa administrar EKS, EC2/VPC, IAM/PassRole, logs e recursos
de balanceamento do laboratório. Criar a organização e conceder esse acesso inicial
está fora desta aula. Não use credenciais root nem transfira o permission set amplo
do laboratório para workloads. Use `aws sso login --profile curso` e
`export AWS_PROFILE=curso`, como no módulo 04; confira conta/role antes de cada sessão.

Use [laboratorios/11-eks](../laboratorios/11-eks/). Ler os arquivos, instalar ferramentas
e executar `terraform validate` não cria infraestrutura. `apply` e a criação do NLB
geram cobrança; preveja a janela e o encerramento. Os arquivos locais `.tfvars`, state
e planos não entram no Git. Não reutilize clusters nem VPCs de produção.
Mantenha o cluster manual dos módulos 09/10 para o projeto final. Este EKS é outro
cluster, temporário; ao encerrá-lo você voltará explicitamente ao kubeconfig manual.

## O que você vai conseguir fazer

- Explicar e provisionar VPC, EKS, managed nodes e add-ons a partir de um plano Terraform.
- Conceder acesso humano à API e acesso de ServiceAccount à AWS, distinguindo-os de RBAC.
- Reproduzir a aplicação, publicar Traefik por NLB com acesso restrito e comprovar EBS/PVC.
- Alterar capacidade do node group, diagnosticar uma falha e comprovar a limpeza de recursos.

Karpenter, EKS Auto Mode e backend Terraform de equipe são comparações posteriores.
O autoscaling de pods já foi praticado no módulo 05; aqui você aprenderá a operação da
capacidade EC2 e o papel que um autoscaler de nós adicionaria.

## Quem opera cada parte

| Responsabilidade | kubeadm em EC2 | EKS deste módulo |
|---|---|---|
| API/etcd e substituição de CP | você | AWS opera o control plane |
| Atualização da minor | kubeadm e operação sua | você planeja/solicita no EKS |
| Workers, capacidade e AMIs | você | node group gerenciado, decisões suas |
| Aplicação, RBAC, SLO e recuperação de dados | você | você |
| Rede, IAM, exposição e custos | você | você |

EKS não oferece SSH ao etcd gerenciado nem executa kubeadm nas suas máquinas de control plane. O trabalho aprendido
continua útil para diagnosticar a fronteira entre aplicação, nó, rede e control plane.
O exercício usa EKS convencional com Managed Node Groups; EKS Auto Mode tem outras
responsabilidades, provisionadores de storage e custos, portanto é uma comparação posterior.

## Leia a infraestrutura antes de criá-la

Terraform descreve recursos por blocos HCL. Um **provider** implementa as chamadas da
API de um fornecedor; uma **variável** fornece uma entrada; um **output** expõe um valor
gerado. O **state** relaciona os endereços do código aos IDs reais na AWS. Um **plan**
compara configuração, state e infraestrutura; `apply` executa as mudanças aprovadas.
Apagar o state não apaga recursos e torna seu gerenciamento mais difícil.

Leia `variables.tf`, `network.tf` e `main.tf` nessa ordem. Exemplo: a referência
`aws_subnet.private[*].id` faz o node group usar as subnets que o mesmo código cria.
O Terraform calcula dependências entre esses recursos; não é uma lista de comandos
para executar por ordem das linhas. As identidades de cluster, nó e EBS têm papéis diferentes.

[`laboratorios/11-eks`](../laboratorios/11-eks/) contém uma VPC `10.80.0.0/16`, três subnets
públicas e três privadas, Internet Gateway, um NAT Gateway com EIP, EKS, três workers
AMD64 AL2023, roles IAM, access entry, add-ons e retenção de logs por sete dias.
Verifique conflito de CIDR antes de interligar essa VPC à sua rede.

Nós privados saem pelo NAT para registros e APIs AWS. O endpoint Kubernetes é privado
para nós e público apenas para seu IPv4 `/32`. Se seu IP mudar, atualize o Terraform.
Uma única saída NAT é simplificação didática: perder sua AZ afeta saída das outras AZs
e pode gerar tráfego entre zonas. O desafio final pede um desenho de saída resiliente.

Antes do `plan`, estime custo para a região e as horas de laboratório: control plane
EKS, três EC2s, discos, NAT por hora/dados, IPv4 público do NAT, logs e tráfego entre
zonas. Adicione depois EBS de PVC, snapshots e balanceadores. Parar os workers não
elimina cobrança do cluster, NAT e volumes. No console **Billing → Budgets**, crie um
orçamento mensal de custo para a conta sandbox, com limite que você escolheu e aviso
para seu e-mail em 50%, 80% e 100%. Orçamento alerta; não impede gastos por si só.
No cálculo de custos do console, recorte a estimativa para esses serviços, região e
horas da janela, incluindo três discos de 30 GiB e depois o NLB. Termine essa tarefa
quando houver uma estimativa registrada, um limite escolhido e o horário de limpeza.

## Preparar Terraform na estação

Se já houver Terraform compatível com `versions.tf`, registre `terraform version` e
preserve a instalação. Para uma estação nova, este exemplo fixa **1.14.5** e compara
o SHA256 publicado. A arquitetura é a da estação, independentemente dos workers AMD64.

```bash
sudo apt-get update
sudo apt-get install -y curl unzip ca-certificates
case "$(uname -m)" in
  x86_64) TF_ARCH=amd64; TF_SHA=ac21c2b9dcd115711f540cbd27ead0596bb4288a917cb56dfa9b25edb3eb6280 ;;
  aarch64) TF_ARCH=arm64; TF_SHA=7dbd03721e8f933ba0426fc292d7a6549a61c0cb1c7c821729f6982c7bce4b05 ;;
  *) printf 'Arquitetura fora do laboratório guiado\n'; exit 1 ;;
esac
TF_TMP=$(mktemp -d)
curl -fL "https://releases.hashicorp.com/terraform/1.14.5/terraform_1.14.5_linux_${TF_ARCH}.zip" \
  -o "$TF_TMP/terraform.zip"
printf '%s  %s\n' "$TF_SHA" "$TF_TMP/terraform.zip" | sha256sum --check - || exit 1
unzip "$TF_TMP/terraform.zip" -d "$TF_TMP"
sudo install -m 0755 "$TF_TMP/terraform" /usr/local/bin/terraform
terraform version
```

Espere checksum `OK` e versão 1.14.5; não extraia se a comparação falhar. O lockfile
do laboratório fixa separadamente o provider AWS. Você ainda não conectou à API AWS.

## Laboratório A — Identidade, região e versões

Use credenciais temporárias por IAM Identity Center/assume-role. Não coloque access keys
nos arquivos Terraform. A identidade que provisiona precisa criar os recursos do exercício
e passar as roles necessárias; a role do acesso kubectl é configurada explicitamente.

```bash
aws sts get-caller-identity
aws configure get region
aws ec2 describe-availability-zones --region us-east-1 \
  --query 'AvailabilityZones[?State==`available`].[ZoneName,ZoneId]' --output table
aws ec2 describe-instance-type-offerings --region us-east-1 --location-type availability-zone \
  --filters Name=instance-type,Values=c7i-flex.large --output table
```

Troque região nos comandos e tfvars consistentemente. Escolha três AZs permitidas pelo
EKS; os nomes `1a/1b/1c` variam entre contas. Neste laboratório `us-east-1`, exclua
o ZoneId `use1-az3`, não suportado por EKS na verificação desta aula. Escolha três
outras AZs disponíveis na sua conta e oferecidas para o tipo EC2. No console EKS,
abra a criação de cluster apenas para verificar que **1.35** aparece entre as versões;
saia sem criar. Caso indisponível no futuro, registre o bloqueio de versão antes de
adaptar o laboratório. AL2023 aqui é a AMI otimizada EKS AMD64, não a AMI kubeadm.

Em **Service Quotas**, confira EC2 On-Demand Standard vCPU (ao menos 6 livres, mais
folga para um quarto nó), EKS clusters/node groups, VPCs, NAT Gateways e Elastic IPs.
Considere uso já existente. Solicite aumento se necessário antes de iniciar a janela.
Esse levantamento termina com três AZs escolhidas e capacidade/quota disponível;
não exige estudar todo o catálogo de serviços.

Copie `terraform.tfvars.example` para `terraform.tfvars` e edite todos os placeholders.
`admin_principal_arn` deve ser ARN IAM de uma role, não o ARN STS da sessão retornada
por `get-caller-identity`. Use a mesma role ao executar `update-kubeconfig`.
Para descobrir seu ARN IAM sem adivinhar o caminho da role SSO:

```bash
SESSION_ROLE=$(aws sts get-caller-identity --query Arn --output text | cut -d/ -f2)
aws iam get-role --role-name "$SESSION_ROLE" --query Role.Arn --output text
curl -fsS https://checkip.amazonaws.com
```

Isso pressupõe a sessão assumida via SSO do pré-requisito. Use o ARN `iam::...:role/...`
retornado em `admin_principal_arn`; acrescente `/32` ao IP público em `admin_public_cidr`.
O CIDR controla acesso ao endpoint, não a autorização dentro dele. VPN/proxy podem mudar
o IP de saída: repita a consulta se houver timeout. Não coloque o ARN STS no tfvars.

Consulte versões compatíveis; não substitua por `latest`:

```bash
for addon in vpc-cni coredns kube-proxy eks-pod-identity-agent aws-ebs-csi-driver; do
  aws eks describe-addon-versions --region us-east-1 \
    --kubernetes-version 1.35 --addon-name "$addon" \
    --query 'addons[].addonVersions[].[addonVersion,architecture,compatibilities]' \
    --output json
done
```

Para cada add-on, escolha a entrada com `architecture` contendo `amd64` e
`compatibilities` indicando `clusterVersion: 1.35` e `defaultVersion: true`.
Copie o `addonVersion` completo, incluindo `-eksbuild.N`, para `addon_versions`.
O objetivo desta consulta delimitada é preencher **cinco versões exatas**, não buscar
automaticamente a maior versão. Se não houver combinação compatível, não execute apply.
O lockfile fixa o provider Terraform, não versões dos add-ons.

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
test ! -e "$HOME/.kube/curso-eks-kubeconfig" || { printf 'Destino já existe: identifique-o antes de continuar.\n'; exit 1; }
aws eks update-kubeconfig --name curso-eks --region us-east-1 --alias curso-eks \
  --kubeconfig "$HOME/.kube/curso-eks-kubeconfig"
chmod 600 "$HOME/.kube/curso-eks-kubeconfig"
export KUBECONFIG="$HOME/.kube/curso-eks-kubeconfig"
kubectl config current-context
kubectl get nodes -L topology.kubernetes.io/zone,kubernetes.io/arch
kubectl -n kube-system get pods
aws eks list-addons --cluster-name curso-eks --region us-east-1
```

Em cada terminal deste módulo, exporte o kubeconfig EKS antes de executar kubectl/Helm.
Ele fica separado de `curso-kubeconfig`; não mescle credenciais do curso com produção.
Use os outputs se mudou o nome/região. Armazene state e planos fora de repositórios
públicos; eles podem conter dados sensíveis. Versione `.terraform.lock.hcl`. Em equipe,
use backend remoto com criptografia, versionamento, controle de acesso e bloqueio.
Criar esse backend é uma extensão de trabalho em equipe; o exercício usa state local
protegido e não depende de configurar um serviço extra antes de prosseguir.

Se um add-on falhar, consulte, por exemplo,
`aws eks describe-addon --cluster-name curso-eks --addon-name aws-ebs-csi-driver --region us-east-1 --query 'addon.{status:status,issues:health.issues}'`
e eventos antes de executar
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
simplificar bootstrap. Migração da identidade do CNI e restrição avançada de IMDS são
aprofundamentos. Nesta aula, prove a separação observando que a role EBS associa-se a
uma ServiceAccount específica enquanto access entry associa uma role humana à API.
Use `kubectl auth can-i --as=system:serviceaccount:curso:default list secrets -n curso`:
o resultado esperado é `no`, independentemente de você ter acesso administrativo por SSO.

## Rede e entrada de tráfego

O Calico do cluster manual fornecia a rede de pods. Aqui Amazon VPC CNI atribui IPs da
VPC: disponibilidade de IPs, ENIs e limites por instância entram no planejamento.
Não aplique o manifest de instalação Calico do kubeadm por cima desse CNI. NetworkPolicy
precisa de suporte e configuração do mecanismo escolhido; existir na API não prova enforcement.

Volte à raiz com `cd ../..`, confirme contexto `curso-eks` e execute
`kubectl apply -k laboratorios/02-workloads`. Espere `rollout status deployment/web -n curso`
e teste `kubectl port-forward -n curso service/web 8080:80`. Pare o túnel após um HTTP 200.
Reproduza **no contexto EKS** a instalação Traefik e o TLS do módulo 03; o certificado
de laboratório e Secret são locais ao cluster e precisam ser criados também aqui.
Confirme primeiro o HTTPS por port-forward. Essa reutilização é um pré-requisito explícito,
não uma conversão automática de objetos do cluster manual.

Agora conecte o mundo AWS ao Service do Traefik. O **AWS Load Balancer Controller**
observa `Service` com classe `service.k8s.aws/nlb` e cria NLB/targets na AWS. Traefik
continua interpretando rotas HTTP/TLS. Um ALB poderia realizar parte do roteamento L7,
mas o laboratório mantém Traefik para reaplicar a configuração e os testes aprendidos no módulo 03.

### Instalar identidade e controller de entrada

O par fixado é **chart 1.14.0 / controller v2.14.0**. A policy baixada abaixo é a
policy de instalação dessa mesma versão: permite descrever rede e gerenciar LBs,
targets e Security Groups usando condições por tags. A role fica ligada apenas à
ServiceAccount do controller no EKS; não amplie a role de todos os nós.

```bash
LBC_TMP=$(mktemp -d)
curl -fL https://raw.githubusercontent.com/kubernetes-sigs/aws-load-balancer-controller/v2.14.0/docs/install/iam_policy.json \
  -o "$LBC_TMP/iam-policy.json"
jq '.Statement[] | {Action,Resource,Condition}' "$LBC_TMP/iam-policy.json"
LBC_POLICY_ARN=$(aws iam create-policy --policy-name curso-eks-lbc \
  --policy-document "file://$LBC_TMP/iam-policy.json" --query Policy.Arn --output text)
LBC_ROLE_ARN=$(aws iam create-role --role-name curso-eks-lbc \
  --assume-role-policy-document '{"Version":"2012-10-17","Statement":[{"Effect":"Allow","Principal":{"Service":"pods.eks.amazonaws.com"},"Action":["sts:AssumeRole","sts:TagSession"]}]}' \
  --query Role.Arn --output text)
aws iam attach-role-policy --role-name curso-eks-lbc --policy-arn "$LBC_POLICY_ARN"
LBC_ASSOC_ID=$(aws eks create-pod-identity-association --region us-east-1 \
  --cluster-name curso-eks --namespace kube-system --service-account aws-load-balancer-controller \
  --role-arn "$LBC_ROLE_ARN" --query association.associationId --output text)
VPC_ID=$(terraform -chdir=laboratorios/11-eks output -raw vpc_id)
helm repo add eks https://aws.github.io/eks-charts
helm repo update
helm show chart eks/aws-load-balancer-controller --version 1.14.0
helm upgrade --install aws-load-balancer-controller eks/aws-load-balancer-controller \
  --version 1.14.0 -n kube-system --set clusterName=curso-eks \
  --set region=us-east-1 --set vpcId="$VPC_ID" \
  --set serviceAccount.name=aws-load-balancer-controller --wait --timeout 5m
kubectl -n kube-system rollout status deployment/aws-load-balancer-controller
```

Execute criação de policy/role apenas uma vez; numa repetição, recupere os ARNs do
inventário em vez de criar recursos homônimos. Registre policy ARN, role ARN e association
ID sem credenciais. O chart instala RBAC/webhook, CRDs auxiliares como TargetGroupBinding
e IngressClassParams e usa certificados próprios do webhook;
não exige cert-manager nesta forma de instalação. Se o rollout falhar, examine pods,
eventos e `kubectl logs -n kube-system deployment/aws-load-balancer-controller`.

### Publicar e testar o NLB

Edite `service.spec.loadBalancerSourceRanges` em
[`traefik-eks-values.yaml`](../laboratorios/11-eks/traefik-eks-values.yaml) para seu
IPv4 público `/32`. O exemplo reservado não autoriza sua estação. O NLB será público,
mas esse intervalo restringe os clientes. Revise antes de aplicar; nunca use `0.0.0.0/0`
para conveniência neste laboratório. Mantenha os values-base da instalação do módulo 03:

```bash
helm upgrade traefik traefik/traefik --version 41.5.0 -n traefik \
  -f laboratorios/03-rede/traefik-values.yaml \
  -f laboratorios/11-eks/traefik-eks-values.yaml --wait --timeout 5m
kubectl -n traefik get service traefik -w
```

Quando aparecer hostname em `EXTERNAL-IP`, pare o watch, anote-o e confirme targets
saudáveis em **EC2 → Target Groups**. O target type `ip` usa os IPs privados dos pods.
Teste HTTP com `curl -f -H 'Host: web.curso.test' http://HOSTNAME_NLB/healthz`.
Para HTTPS, reutilize o certificado confiado e o hostname do exercício TLS03:
`curl --cacert CAMINHO_DO_CERTIFICADO --connect-to web.curso.test:443:HOSTNAME_NLB:443 https://web.curso.test/healthz`.
`--connect-to` muda o destino TCP, preservando SNI e validação do nome. Espere HTTP 200;
não remova a validação TLS com `-k`. Se a rota TLS usa outro nome no seu lab03, use-o.
Registre ARN do LB e targets. DNS público com domínio próprio é uma evolução opcional.

## Laboratório D — EBS e uma falha reversível

Volte à raiz do repositório e aplique somente no EKS de estudo:

```bash
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

Exemplo guiado de capacidade: em `main.tf`, altere apenas `desired_size` de 3 para 4
no node group. A partir da raiz do repositório:

```bash
terraform -chdir=laboratorios/11-eks plan -out=capacidade.tfplan
terraform -chdir=laboratorios/11-eks show capacidade.tfplan
# Confirme mudança de tamanho, sem substituição do cluster/VPC, antes de aplicar:
terraform -chdir=laboratorios/11-eks apply capacidade.tfplan
kubectl get nodes
aws eks describe-nodegroup --cluster-name curso-eks --nodegroup-name amd64-lab \
  --region us-east-1 --query nodegroup.scalingConfig
```

Espere o quarto nó Ready e a API AWS informando `desiredSize: 4`.
Volte a 3 pelo mesmo caminho; mantenha a janela de laboratório porque reduzir capacidade
pode interromper pods e exigir reagendamento. Não execute a redução durante o teste de PVC.

Desafio delimitado: o cenário tem pods Pending por requests de CPU e máximos de quatro
nós. Usando `kubectl describe pod` e o node group observado, explique a diferença entre
diminuir requests sem medição, aumentar capacidade manualmente e usar um autoscaler.
Entregue a evidência de quatro nós e do retorno a três, um limite de custo e a resposta
à pergunta: quem observaria os pods pendentes para decidir criar máquinas?
Karpenter faz essa observação por controllers e declara limites via `NodePool`; o
`EC2NodeClass` descreve infraestrutura AWS. Instalar e operar Karpenter é aprofundamento
opcional, não uma dependência oculta para encerrar este módulo.

## Encerrar o laboratório e comprovar a limpeza

Antes de destruir EKS, remova Ingress/Services LoadBalancer que criou e aguarde a remoção
dos LBs pelo controller. Registre ID do EBS do PV, decida se haverá snapshot e remova
o pod/PVC deste exercício. `Retain` deixa volume e PV para tratamento manual.

Para o NLB criado acima, execute `helm uninstall traefik -n traefik` e acompanhe a
exclusão do LB/targets no console. **Só então** remova o controller e sua identidade,
usando os valores registrados durante a criação:

```bash
helm uninstall aws-load-balancer-controller -n kube-system
aws eks delete-pod-identity-association --cluster-name curso-eks --region us-east-1 \
  --association-id "$LBC_ASSOC_ID"
aws iam detach-role-policy --role-name curso-eks-lbc --policy-arn "$LBC_POLICY_ARN"
aws iam delete-role --role-name curso-eks-lbc
aws iam delete-policy --policy-arn "$LBC_POLICY_ARN"
```

Esses recursos IAM foram criados por CLI e não constam no state Terraform. Se perdeu
as variáveis da sessão, recupere IDs do inventário e confirme com list/get antes de excluir.

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

Volte à estação do laboratório principal antes de iniciar o módulo 12:

```bash
export KUBECONFIG="$HOME/.kube/curso-kubeconfig"
kubectl config current-context
kubectl get nodes
kubectl -n curso get deployment/web service/web
```

Confirme os nós do cluster **manual**, não o endpoint EKS já removido. Preserve o
arquivo de acesso EKS somente enquanto útil para auditoria local; nunca o publique.

## Fechamento

EKS remove a operação direta dos seus API servers/etcd, mas mantém decisões de rede,
capacidade, identidade e recuperação sob sua responsabilidade. Explique a cadeia
pessoa → access entry → API e a cadeia pod → ServiceAccount → Pod Identity → AWS.

Avance com sete provas: plano revisado, três nós Ready, versão dos add-ons registrada,
HTTP/TLS pelo NLB restrito, arquivo persistente após recriar Pod, quarto nó criado e
removido, inventário de limpeza incluindo recursos fora do state. Registre também o
custo previsto/observado. Quem só fez validate concluiu a preparação offline, não a
execução EKS. Karpenter, backend de equipe e ALB são aprofundamentos, sem leitura
externa obrigatória para os resultados acima.

## Referências opcionais

Fontes verificadas em 12/09/2026; aprofundamentos para outras arquiteturas e atualizações.

- [Provider AWS: EKS](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/eks_cluster) amplia argumentos e responsabilidades dos recursos Terraform.
- [Verificar Terraform](https://developer.hashicorp.com/terraform/tutorials/cli/verify-archive) acrescenta verificação de assinatura aos checksums do exercício.
- [Rede EKS](https://docs.aws.amazon.com/eks/latest/userguide/network-reqs.html) detalha outras regiões, IPv6 e clusters privados.
- [VPC CNI](https://docs.aws.amazon.com/eks/latest/userguide/managing-vpc-cni.html) aprofunda ENIs, IPs e operação de rede.
- [Access entries](https://docs.aws.amazon.com/eks/latest/userguide/access-entries.html) e [Pod Identity](https://docs.aws.amazon.com/eks/latest/userguide/pod-identities.html) ampliam políticas, associações e cenários entre contas.
- [EBS CSI](https://docs.aws.amazon.com/eks/latest/userguide/ebs-csi.html) detalha snapshots, KMS e diferenças do Auto Mode.
- [Load Balancer Controller](https://kubernetes-sigs.github.io/aws-load-balancer-controller/latest/) expande o exercício para ALB e outras configurações de entrada.
- [Karpenter](https://karpenter.sh/docs/concepts/) apresenta o projeto opcional de provisão automática de nós.
- [Preços EKS](https://aws.amazon.com/eks/pricing/) explica componentes de cobrança para comparar alternativas além da estimativa guiada no console.
