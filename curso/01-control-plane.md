# 01 — Construir e compreender o control plane

Você vai criar a infraestrutura de laboratório na AWS, montar um cluster e observar quem mantém cada parte funcionando. Instalar manualmente, aqui, significa criar os recursos AWS um a um e depois preparar hosts, runtime, pacotes e rede em etapas verificáveis com kubeadm; não escrever seu próprio instalador nem montar toda a PKI sem ferramentas.

Esta primeira execução não usa Terraform. A estação local não dispõe da capacidade necessária para três VMs de 4 GiB, por isso os hosts serão EC2 descartáveis. Essa é uma escolha do laboratório, não uma exigência do Kubernetes. Depois de comprovar e destruir manualmente o primeiro cluster, o Terraform já fornecido poderá reconstruir a base dos módulos seguintes; ele não é conteúdo nem critério de aprovação desta aula.

## Antes de começar

**Duração:** 20–28 horas, incluindo infraestrutura, diagnóstico e destruição. **Pré-requisito:** preparação do módulo 00, conta AWS de laboratório com teto de gasto definido e uma identidade administrativa autorizada. Você criará três EC2 Ubuntu 24.04 novas, numa VPC exclusiva e separada de produção.

**LOCAL** é uma estação Linux com Bash, este repositório, AWS CLI v2 autenticada, `curl`, `ssh`, `scp` e `sha256sum`. Em Ubuntu, prepare as ferramentas básicas com `sudo apt-get update` e `sudo apt-get install -y ca-certificates curl openssh-client coreutils`. Confirme `aws --version` e `aws sts get-caller-identity` antes de criar qualquer recurso; pare se a conta ou a identidade não forem as esperadas. Não precisa instalar kubectl previamente: a etapa 3 ensina isso. Os arquivos de [teste de rede](../laboratorios/01-control-plane/rede.yaml) são parte da prática e terão seu papel explicado antes de aplicar.

Separe a aula em cinco sessões: infraestrutura AWS; arquitetura e preparação dos hosts; runtime e pacotes; inicialização e rede; falha, evidência e destruição. Se interromper antes do fim, registre quais recursos continuam cobrando. O primeiro CP ainda não é alta disponibilidade. Não há aplicação com dados persistentes neste capítulo.

## O que você vai conseguir fazer

- Construir e explicar a rede AWS mínima e isolada que sustenta os três nodes.
- Explicar o papel da API, etcd, controllers, scheduler, kubelet, runtime e CNI.
- Instalar um CP e dois workers com versões registradas e endpoint privado estável.
- Administrar esse cluster por identidade IAM, túnel privado e kubeconfig isolado.
- Comprovar rede entre nós, DNS e recuperação de um kubelet parado.
- Destruir manualmente os recursos cobrados e comprovar que não ficaram resíduos.

## O que acontece ao pedir um Deployment

Um objeto é um registro na API: tem tipo, nome e campos. A intenção costuma aparecer em `spec`; as condições observadas, em `status`. Um Pod é a unidade que contém um ou mais containers e é atribuída a um nó. Um Deployment declara como manter e atualizar réplicas de uma aplicação. Nesta aula isso explica a arquitetura; escrever Deployments será a prática do módulo 02.

`kubectl` envia um objeto ao API Server. A API autentica, autoriza, valida e persiste o estado no etcd. O controller de Deployment mantém ReplicaSets; o de ReplicaSet mantém Pods. O scheduler associa cada Pod ainda sem nó a um Node adequado. O kubelet daquele nó pede ao runtime que prepare o sandbox e os containers; a integração CNI configura a rede. Os componentes observam a API e reconciliam continuamente. O API Server não executa seu container e o scheduler não copia imagens.

Pense em uma solicitação de duas réplicas: primeiro há um registro com essa intenção; depois aparecem os Pods; por fim, os nós executam os containers e publicam suas condições. São etapas assíncronas. Uma resposta bem-sucedida de `kubectl apply` significa que a API aceitou o pedido, não que a aplicação já está pronta.

**CRI** é a interface entre kubelet e runtime; **containerd** é o runtime escolhido. **CNI** é a interface usada para integrar a rede de Pods; **Calico** é a implementação escolhida. **CoreDNS** responde consultas de nomes internos. **kube-proxy**, instalado por kubeadm nesta configuração, programa o encaminhamento dos endereços virtuais dos Services para seus backends. CNI e kube-proxy resolvem partes diferentes do caminho de rede.

`kubeadm` prepara o cluster e seus certificados; `kubelet` é o agente de cada nó; `kubectl` é um cliente da API. Neste laboratório, API Server, scheduler, controller-manager e etcd são **static Pods**: o kubelet os mantém a partir de arquivos locais. Os objetos vistos pela API são seus mirror Pods. Isso permite iniciar o próprio control plane antes de haver scheduler funcional. Apagar só um mirror Pod pela API não remove o arquivo nem desativa o componente; o kubelet continua responsável por ele.

## Topologia e escolhas antes dos comandos

| Máquina/rede | Base do laboratório | Por quê |
| --- | --- | --- |
| cp1 | 2 vCPU, 4 GiB RAM, 30 GiB gp3 | Folga para sistema, API e etcd; não é sizing universal |
| worker1 e worker2 | 2 vCPU, 4 GiB RAM, 30 GiB gp3 cada | Dois destinos para testar scheduling e rede |
| SO e arquitetura | Ubuntu 24.04 AMD64 | Permite usar `c7i-flex.large`, com 4 GiB, no plano Free Tier atual |
| Região e AZ | `us-east-1`, uma AZ disponível | Latência inter-node simples; não representa HA entre zonas |
| VPC | `10.42.0.0/16` | Fronteira descartável exclusiva do laboratório |
| Subnet | `10.42.10.0/24` | Rede dos três nodes e do endpoint administrativo |
| IPs privados | `.10` cp1, `.11` worker1, `.12` worker2 | Endereços estáveis durante esta execução |
| Pods | `172.20.0.0/16` | Faixa usada pelo Calico, distinta da VPC |
| Services | `10.96.0.0/12` | Faixa virtual distinta da VPC e dos Pods |
| Kubernetes | Linha 1.35, patch explicitamente selecionado abaixo | Base didática e de exame desta edição |
| CNI | Calico 3.32.2, VXLAN, BGP desabilitado | Rede entre nós e suporte a NetworkPolicy |
| Endpoint | `lab-k8s.internal:6443` | Nome estável desde o primeiro init, útil na futura HA |

Use uma AZ inicialmente. O EBS raiz da EC2 guarda sistema, containerd e `/var/lib/etcd`; ele existe antes do Kubernetes e não é um PVC. Não há storage de aplicação neste módulo. As três EC2 recebem IPv4 público temporário exclusivamente para alcançar repositórios e registries por um Internet Gateway; o Security Group não permite administração direta pela Internet. AMD64 é a arquitetura escolhida para este ambiente, não uma exigência do Kubernetes; ARM64 também funciona com pacotes e imagens compatíveis.

Os CIDRs acima **não podem se sobrepor** entre si nem a redes que venham a ser conectadas à VPC. Neste laboratório não haverá VPN, peering nem conexão com a LAN; preserve exatamente `10.42.0.0/16` para a VPC, `172.20.0.0/16` para Pods e `10.96.0.0/12` para Services. Uma futura integração de redes exigirá revisar essas faixas antes de criar conectividade.

Não criaremos uma zona Route 53. Em todos os hosts, `/etc/hosts` fará `lab-k8s.internal` apontar para `10.42.10.10`. Na estação LOCAL, esse mesmo nome apontará para `127.0.0.1` e só alcançará a API enquanto o túnel estiver aberto. O nome em `/etc/hosts` não é propagado automaticamente aos Pods, que usam CoreDNS; os componentes internos podem acessar `kubernetes.default.svc`.

Um load balancer TCP futuro assumirá esse nome. `--control-plane-endpoint` evita construir os certificados e a configuração em torno de um IP específico. Hoje o nome representa apenas cp1; ele só passará a oferecer acesso a vários CPs quando instalarmos e testarmos o balanceador no módulo 10.

## Firewall antes da inicialização

Use dois Security Groups: `nodes` nos três hosts e `eice` no EC2 Instance Connect Endpoint. O endpoint recebe autorização por IAM; seu SG não precisa de regra de entrada. Com `preserve-client-ip=false`, os nodes reconhecem como origem o SG do endpoint. A tabela descreve entrada; Security Groups são stateful, enquanto NACLs são stateless.

| Destino | Porta/protocolo | Origem autorizada |
| --- | --- | --- |
| Todos os hosts | TCP 22 | Somente o SG `eice` |
| CP | TCP 6443 | Somente o SG `nodes`; LOCAL usa port forwarding por SSH |
| Todos os hosts | TCP 10250 | CP; posteriormente componentes autorizados, como metrics-server |
| Todos os hosts | UDP 4789 | Somente nós do cluster, VXLAN |
| Todos os hosts | TCP 5473 | Somente nós, para Calico Typha |
| CPs futuros | TCP 2379–2380 | Somente outros CPs; não expor etcd aos workers |

O SG `eice` permite saída somente TCP 22 para o SG `nodes`. O SG `nodes` mantém saída para `0.0.0.0/0`, necessária a DNS, tempo, repositórios e registries pelo Internet Gateway. Isso não cria entrada da Internet. Scheduler/controller-manager usam portas locais; não abra 10257/10259 nem toda a faixa NodePort. O único SG de nodes cobre CP e workers, portanto as regras que referenciam a si próprio autorizam o tráfego privado entre os três.

Calico precisa controlar suas interfaces e regras de rede. Em hosts novos deste lab, evite firewalld/UFW concorrendo com ele; mantenha a restrição de perímetro nos SGs. Verifique com `systemctl is-active firewalld`, `systemctl is-active ufw` e, se instalado, `sudo ufw status`. Somente depois de confirmar SGs, rotas e uma segunda sessão SSH funcional, desative o gerenciador ativo do host dedicado (`sudo ufw disable` ou `sudo systemctl disable --now firewalld`, conforme o caso). Serviço ausente não precisa ser instalado ou desativado. Não replique essa decisão em hosts de produção.

Se `systemctl is-active NetworkManager` indicar `active`, use `sudoedit /etc/NetworkManager/conf.d/calico.conf` para criar a configuração abaixo; se o arquivo já existir, preserve outras configurações e combine a lista. Depois execute `sudo nmcli general reload conf` e confirme que o SSH continua funcional. Se NetworkManager não estiver ativo, pule esse ajuste.

```ini
[keyfile]
unmanaged-devices=interface-name:cali*;interface-name:tunl*;interface-name:vxlan.calico;interface-name:vxlan-v6.calico;interface-name:wireguard.cali;interface-name:wg-v6.cali
```

## 0. Criar a infraestrutura AWS manualmente

A primeira execução começa na infraestrutura, sem Terraform e sem copiar comandos do diretório de automação. Os comandos abaixo tornam a criação repetível e auditável, mas cada chamada ainda é uma decisão manual: leia a operação, execute uma por vez, confira a resposta e só então prossiga. Execute a partir da raiz do repositório.

### Identidade, região e padrão de tags

Tags não limitam gastos nem substituem um orçamento. Elas dão contexto ao inventário e, depois de ativadas como **cost allocation tags**, permitem filtrar custos. Use as chaves exatamente como estão, inclusive maiúsculas e minúsculas:

| Chave | Valor neste laboratório | Finalidade |
| --- | --- | --- |
| `Projeto` | `curso-kubernetes` | Agrupar toda a trilha |
| `Ambiente` | `laboratorio` | Separar estudo de outros ambientes |
| `Modulo` | `m01` | Classificação informativa para relatórios; nunca seleção operacional |
| `ClusterName` | `kubelab` | Identidade lógica estável do laboratório |
| `Owner` | identificador público do responsável | Indicar quem revisa e remove |
| `CostCenter` | `estudo-kubernetes` | Dimensão financeira estável |
| `ManagedBy` | `manual` | Distinguir esta execução do futuro Terraform |
| `LabRun` | `run-AAAAMMDDThhmmssZ` | Correlacionar de forma imutável uma execução específica |
| `ExpiresOn` | data UTC do dia seguinte | Sinalizar quando o laboratório deveria deixar de existir |
| `Name` | `kubelab-${LabRun}-${componente}` | Busca visual imediata e nomes únicos por execução |

`ExpiresOn` é apenas metadado; a AWS não apagará recursos nessa data. Não coloque e-mail, credencial, cliente ou informação confidencial em tags. `LabRun` é a correlação imutável da execução; `Modulo` é apenas contexto informativo e pode mudar entre sessões. `Modulo`, `Name`, `Owner`, `CostCenter` e as demais tags descritivas não podem autorizar acesso, determinar rede, selecionar estado ou justificar exclusão. Conta, região e IDs registrados definem o alvo; `LabRun` apenas confirma que esses IDs pertencem à mesma execução.

**LOCAL — defina o contexto e crie um inventário local ignorado pelo Git:**

```bash
export AWS_REGION=us-east-1
export AWS_PAGER=""
AWS_ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)
aws sts get-caller-identity
aws freetier get-account-plan-state \
  --region "$AWS_REGION" \
  --query '{plano:accountPlanType,status:accountPlanStatus}'
aws ec2 describe-instance-types \
  --region "$AWS_REGION" \
  --instance-types c7i-flex.large \
  --query 'InstanceTypes[0].{tipo:InstanceType,vcpus:VCpuInfo.DefaultVCpus,memoriaMiB:MemoryInfo.SizeInMiB,elegivel:FreeTierEligible,arquitetura:ProcessorInfo.SupportedArchitectures}'

read -r -p 'Owner para as tags (ex.: seu usuário GitHub): ' LAB_OWNER
[[ "$LAB_OWNER" =~ ^[a-zA-Z0-9._-]+$ ]] || { printf 'Owner inválido.\n'; exit 1; }

LAB_RUN=$(date -u +run-%Y%m%dT%H%M%SZ)
EXPIRES_ON=$(date -u -d '+1 day' +%F)
CLUSTER_NAME=kubelab
NAME_PREFIX="kubelab-$LAB_RUN"
LAB_STATE=.env.m01-aws
test ! -e "$LAB_STATE" || { printf '%s já existe; não sobrescreva o inventário de outra execução.\n' "$LAB_STATE"; exit 1; }
umask 077
: > "$LAB_STATE"

record_state() {
  printf '%s=%q\n' "$1" "$2" >> "$LAB_STATE"
}

record_state AWS_ACCOUNT_ID "$AWS_ACCOUNT_ID"
record_state AWS_REGION "$AWS_REGION"
record_state LAB_OWNER "$LAB_OWNER"
record_state LAB_RUN "$LAB_RUN"
record_state EXPIRES_ON "$EXPIRES_ON"
record_state CLUSTER_NAME "$CLUSTER_NAME"
record_state NAME_PREFIX "$NAME_PREFIX"

COMMON_TAGS="{Key=Projeto,Value=curso-kubernetes},{Key=Ambiente,Value=laboratorio},{Key=Modulo,Value=m01},{Key=ClusterName,Value=$CLUSTER_NAME},{Key=Owner,Value=$LAB_OWNER},{Key=CostCenter,Value=estudo-kubernetes},{Key=ManagedBy,Value=manual},{Key=LabRun,Value=$LAB_RUN},{Key=ExpiresOn,Value=$EXPIRES_ON}"

tag_spec() {
  local resource_type=$1
  local component=$2
  printf 'ResourceType=%s,Tags=[%s,{Key=Name,Value=%s-%s}]' "$resource_type" "$COMMON_TAGS" "$NAME_PREFIX" "$component"
}
record_state COMMON_TAGS "$COMMON_TAGS"
```

O arquivo `.env.m01-aws` contém IDs, não segredos, mas é deliberadamente ignorado pelo Git e deve ficar com modo 600. Ele será a autoridade para a destruição; tags serão uma verificação independente. Antes de criar algo, confira se `AWS_ACCOUNT_ID` é a conta de laboratório e se o plano e a elegibilidade exibidos são os esperados. Créditos e elegibilidade variam por conta, região e data.

Conclua a infraestrutura na mesma sessão de shell. Se o terminal fechar, não repita o trecho que cria ou esvazia `.env.m01-aws`: execute `source .env.m01-aws` e redefina somente as funções `record_state` e `tag_spec` exatamente como acima. Depois consulte o inventário AWS pelos IDs já registrados antes de retomar.

Escolha uma AZ que ofereça o tipo adotado e registre a escolha:

```bash
aws ec2 describe-instance-type-offerings \
  --region "$AWS_REGION" \
  --location-type availability-zone \
  --filters Name=instance-type,Values=c7i-flex.large \
  --query 'InstanceTypeOfferings[].Location' \
  --output table

read -r -p 'AZ escolhida em us-east-1: ' LAB_AZ
[[ "$LAB_AZ" =~ ^us-east-1[a-z]$ ]] || { printf 'AZ inválida.\n'; exit 1; }
record_state LAB_AZ "$LAB_AZ"

AMI_ID=$(aws ssm get-parameter \
  --region "$AWS_REGION" \
  --name /aws/service/canonical/ubuntu/server/24.04/stable/current/amd64/hvm/ebs-gp3/ami-id \
  --query Parameter.Value \
  --output text)
ROOT_DEVICE=$(aws ec2 describe-images \
  --region "$AWS_REGION" \
  --image-ids "$AMI_ID" \
  --query 'Images[0].RootDeviceName' \
  --output text)
aws ec2 describe-images \
  --region "$AWS_REGION" \
  --image-ids "$AMI_ID" \
  --query 'Images[0].{id:ImageId,nome:Name,arquitetura:Architecture,raiz:RootDeviceType,device:RootDeviceName}'
record_state AMI_ID "$AMI_ID"
record_state ROOT_DEVICE "$ROOT_DEVICE"
```

A consulta usa o parâmetro público da Canonical e pode devolver outra AMI numa reconstrução futura. Registrar o ID torna essa mudança visível.

### Criar VPC, subnet e rota de saída

```bash
VPC_ID=$(aws ec2 create-vpc \
  --region "$AWS_REGION" \
  --cidr-block 10.42.0.0/16 \
  --tag-specifications "$(tag_spec vpc vpc)" \
  --query Vpc.VpcId --output text)
record_state VPC_ID "$VPC_ID"
aws ec2 wait vpc-available --region "$AWS_REGION" --vpc-ids "$VPC_ID"
aws ec2 modify-vpc-attribute --region "$AWS_REGION" --vpc-id "$VPC_ID" --enable-dns-support
aws ec2 modify-vpc-attribute --region "$AWS_REGION" --vpc-id "$VPC_ID" --enable-dns-hostnames

IGW_ID=$(aws ec2 create-internet-gateway \
  --region "$AWS_REGION" \
  --tag-specifications "$(tag_spec internet-gateway igw)" \
  --query InternetGateway.InternetGatewayId --output text)
record_state IGW_ID "$IGW_ID"
aws ec2 attach-internet-gateway --region "$AWS_REGION" --internet-gateway-id "$IGW_ID" --vpc-id "$VPC_ID"

SUBNET_ID=$(aws ec2 create-subnet \
  --region "$AWS_REGION" \
  --vpc-id "$VPC_ID" \
  --availability-zone "$LAB_AZ" \
  --cidr-block 10.42.10.0/24 \
  --tag-specifications "$(tag_spec subnet subnet)" \
  --query Subnet.SubnetId --output text)
record_state SUBNET_ID "$SUBNET_ID"

ROUTE_TABLE_ID=$(aws ec2 create-route-table \
  --region "$AWS_REGION" \
  --vpc-id "$VPC_ID" \
  --tag-specifications "$(tag_spec route-table routes)" \
  --query RouteTable.RouteTableId --output text)
record_state ROUTE_TABLE_ID "$ROUTE_TABLE_ID"
aws ec2 create-route \
  --region "$AWS_REGION" \
  --route-table-id "$ROUTE_TABLE_ID" \
  --destination-cidr-block 0.0.0.0/0 \
  --gateway-id "$IGW_ID"
ROUTE_ASSOCIATION_ID=$(aws ec2 associate-route-table \
  --region "$AWS_REGION" \
  --route-table-id "$ROUTE_TABLE_ID" \
  --subnet-id "$SUBNET_ID" \
  --query AssociationId --output text)
record_state ROUTE_ASSOCIATION_ID "$ROUTE_ASSOCIATION_ID"
```

A subnet é chamada pública porque sua tabela possui rota `0.0.0.0/0` para o Internet Gateway. Isso, sozinho, não inicia conexões contra as instâncias: elas terão IPv4 público temporário, mas o SG continuará sem entrada da Internet.

### Criar os Security Groups e o endpoint administrativo

```bash
NODE_SG_ID=$(aws ec2 create-security-group \
  --region "$AWS_REGION" \
  --vpc-id "$VPC_ID" \
  --group-name "$NAME_PREFIX-nodes" \
  --description "Nodes do laboratório kubeadm m01" \
  --tag-specifications "$(tag_spec security-group nodes)" \
  --query GroupId --output text)
record_state NODE_SG_ID "$NODE_SG_ID"

EICE_SG_ID=$(aws ec2 create-security-group \
  --region "$AWS_REGION" \
  --vpc-id "$VPC_ID" \
  --group-name "$NAME_PREFIX-eice" \
  --description "Saida do EC2 Instance Connect Endpoint" \
  --tag-specifications "$(tag_spec security-group eice)" \
  --query GroupId --output text)
record_state EICE_SG_ID "$EICE_SG_ID"

aws ec2 authorize-security-group-ingress --region "$AWS_REGION" --group-id "$NODE_SG_ID" \
  --ip-permissions "IpProtocol=tcp,FromPort=22,ToPort=22,UserIdGroupPairs=[{GroupId=$EICE_SG_ID,Description=SSH-via-EICE}]"
aws ec2 authorize-security-group-ingress --region "$AWS_REGION" --group-id "$NODE_SG_ID" \
  --ip-permissions "IpProtocol=tcp,FromPort=6443,ToPort=6443,UserIdGroupPairs=[{GroupId=$NODE_SG_ID,Description=API-entre-nodes}]"
aws ec2 authorize-security-group-ingress --region "$AWS_REGION" --group-id "$NODE_SG_ID" \
  --ip-permissions "IpProtocol=tcp,FromPort=10250,ToPort=10250,UserIdGroupPairs=[{GroupId=$NODE_SG_ID,Description=Kubelet-entre-nodes}]"
aws ec2 authorize-security-group-ingress --region "$AWS_REGION" --group-id "$NODE_SG_ID" \
  --ip-permissions "IpProtocol=udp,FromPort=4789,ToPort=4789,UserIdGroupPairs=[{GroupId=$NODE_SG_ID,Description=Calico-VXLAN}]"
aws ec2 authorize-security-group-ingress --region "$AWS_REGION" --group-id "$NODE_SG_ID" \
  --ip-permissions "IpProtocol=tcp,FromPort=5473,ToPort=5473,UserIdGroupPairs=[{GroupId=$NODE_SG_ID,Description=Calico-Typha}]"

aws ec2 revoke-security-group-egress --region "$AWS_REGION" --group-id "$EICE_SG_ID" \
  --ip-permissions 'IpProtocol=-1,IpRanges=[{CidrIp=0.0.0.0/0}]'
aws ec2 authorize-security-group-egress --region "$AWS_REGION" --group-id "$EICE_SG_ID" \
  --ip-permissions "IpProtocol=tcp,FromPort=22,ToPort=22,UserIdGroupPairs=[{GroupId=$NODE_SG_ID,Description=SSH-para-nodes}]"

EICE_ID=$(aws ec2 create-instance-connect-endpoint \
  --region "$AWS_REGION" \
  --subnet-id "$SUBNET_ID" \
  --security-group-ids "$EICE_SG_ID" \
  --no-preserve-client-ip \
  --tag-specifications "$(tag_spec instance-connect-endpoint eice)" \
  --query InstanceConnectEndpoint.InstanceConnectEndpointId \
  --output text)
record_state EICE_ID "$EICE_ID"

while :; do
  EICE_STATE=$(aws ec2 describe-instance-connect-endpoints \
    --region "$AWS_REGION" \
    --instance-connect-endpoint-ids "$EICE_ID" \
    --query 'InstanceConnectEndpoints[0].State' --output text)
  printf 'EICE: %s\n' "$EICE_STATE"
  [[ "$EICE_STATE" == create-complete ]] && break
  [[ "$EICE_STATE" == create-failed ]] && exit 1
  sleep 5
done
```

O endpoint não é uma regra de rede pública: IAM autoriza a abertura do túnel; os dois SGs autorizam apenas o salto TCP 22 do endpoint aos nodes. Não existe EC2 key pair persistente neste laboratório.

### Criar os três nodes

A função abaixo mantém a mesma configuração e as mesmas tags em instância, EBS raiz e interface de rede. Todo `Name` segue `kubelab-${LabRun}-${componente}`; por exemplo, `kubelab-run-20260915T120000Z-cp1`. `LabRun` permanece disponível também como tag independente, sem incorporar `Modulo`.

```bash
launch_node() {
  local node_name=$1
  local private_ip=$2

  aws ec2 run-instances \
    --region "$AWS_REGION" \
    --image-id "$AMI_ID" \
    --instance-type c7i-flex.large \
    --count 1 \
    --network-interfaces "DeviceIndex=0,SubnetId=$SUBNET_ID,Groups=$NODE_SG_ID,AssociatePublicIpAddress=true,PrivateIpAddress=$private_ip" \
    --block-device-mappings "DeviceName=$ROOT_DEVICE,Ebs={VolumeSize=30,VolumeType=gp3,Iops=3000,Throughput=125,Encrypted=true,DeleteOnTermination=true}" \
    --metadata-options HttpEndpoint=enabled,HttpTokens=required,HttpPutResponseHopLimit=1 \
    --instance-initiated-shutdown-behavior stop \
    --ebs-optimized \
    --tag-specifications \
      "$(tag_spec instance "$node_name")" \
      "$(tag_spec volume "$node_name-root")" \
      "$(tag_spec network-interface "$node_name-eni")" \
    --query 'Instances[0].InstanceId' \
    --output text
}

CP_INSTANCE_ID=$(launch_node cp1 10.42.10.10)
record_state CP_INSTANCE_ID "$CP_INSTANCE_ID"
WORKER1_INSTANCE_ID=$(launch_node worker1 10.42.10.11)
record_state WORKER1_INSTANCE_ID "$WORKER1_INSTANCE_ID"
WORKER2_INSTANCE_ID=$(launch_node worker2 10.42.10.12)
record_state WORKER2_INSTANCE_ID "$WORKER2_INSTANCE_ID"

aws ec2 wait instance-running --region "$AWS_REGION" \
  --instance-ids "$CP_INSTANCE_ID" "$WORKER1_INSTANCE_ID" "$WORKER2_INSTANCE_ID"
aws ec2 wait instance-status-ok --region "$AWS_REGION" \
  --instance-ids "$CP_INSTANCE_ID" "$WORKER1_INSTANCE_ID" "$WORKER2_INSTANCE_ID"
aws ec2 describe-instances --region "$AWS_REGION" \
  --instance-ids "$CP_INSTANCE_ID" "$WORKER1_INSTANCE_ID" "$WORKER2_INSTANCE_ID" \
  --query 'Reservations[].Instances[].{nome:Tags[?Key==`Name`]|[0].Value,id:InstanceId,estado:State.Name,privado:PrivateIpAddress,publico:PublicIpAddress,az:Placement.AvailabilityZone}' \
  --output table
aws resourcegroupstaggingapi get-resources \
  --region "$AWS_REGION" \
  --tag-filters "Key=LabRun,Values=$LAB_RUN" \
  --query 'ResourceTagMappingList[].ResourceARN' \
  --output table
```

Não há `--key-name`: o acesso usa chave efêmera publicada pelo EC2 Instance Connect. A função recebe somente nome e IP do node para reduzir diferenças acidentais entre as três criações.

Conecte-se a cada host substituindo apenas o ID:

```bash
source .env.m01-aws
aws ec2-instance-connect ssh \
  --region "$AWS_REGION" \
  --instance-id "$CP_INSTANCE_ID" \
  --os-user ubuntu \
  --connection-type eice \
  --eice-options "endpointId=$EICE_ID,maxTunnelDuration=3600"
```

Antes de iniciar a configuração Linux, confira no console **Billing and Cost Management → Cost allocation tags** se `Projeto`, `Ambiente`, `Modulo`, `ClusterName`, `Owner`, `CostCenter`, `ManagedBy` e `LabRun` já aparecem e ative-as. A disponibilização para Cost Explorer pode levar até 24 horas; portanto o fechamento imediato usa IDs e inventário, e a revisão financeira ocorre depois. Custos que não aceitam essas tags ainda precisam ser revisados por conta, região e serviço.


## 1. Preparar todos os hosts

**TODOS OS HOSTS — repetir por SSH, conferindo o nome antes de sudo.** Use nomes únicos `cp1`, `worker1` e `worker2`; se necessário, ajuste com `sudo hostnamectl set-hostname NOME_REAL` e reconecte. Depois use `sudoedit /etc/hosts` e acrescente estas três linhas em cada host:

```text
10.42.10.10 lab-k8s.internal cp1
10.42.10.11 worker1
10.42.10.12 worker2
```

Confirme a resolução antes das demais mudanças:

```bash
hostnamectl
uname -m
ip -br address
ip route
getent hosts lab-k8s.internal
timedatectl status
free -h
df -h /
swapon --show
sudo apt-get update
sudo apt-get install -y ca-certificates curl gpg apt-transport-https
sudo swapoff -a
sudoedit /etc/fstab
```

Em `/etc/fstab`, comente somente a entrada de swap, se existir. Se a imagem usa zram ou uma unidade swap gerada, desabilite sua fonte de configuração também. A escolha didática é swap desabilitado; `swapon --show` deve permanecer vazio após reiniciar. Não ignore uma falha de preflight para prosseguir sem entender a causa.

Use `sudoedit /etc/modules-load.d/kubernetes.conf` e salve:

```text
overlay
br_netfilter
```

Use `sudoedit /etc/sysctl.d/99-kubernetes.conf` e salve:

```ini
net.ipv4.ip_forward = 1
net.bridge.bridge-nf-call-iptables = 1
net.bridge.bridge-nf-call-ip6tables = 1
```

```bash
# TODOS OS HOSTS
sudo modprobe overlay
sudo modprobe br_netfilter
sudo sysctl --system
sysctl net.ipv4.ip_forward net.bridge.bridge-nf-call-iptables
```

## 2. Instalar e verificar containerd

**TODOS OS HOSTS.** A imagem Ubuntu pode trazer versões diferentes do pacote. Consulte, selecione a versão exata do repositório da distribuição e registre-a; não misture os pacotes `containerd` e `containerd.io`.

```bash
apt-cache madison containerd
read -r -p 'Versão exata do pacote containerd listada acima: ' RUNTIME_DEB
test -n "$RUNTIME_DEB" || { printf 'Escolha uma versão antes de continuar.\n'; exit 1; }
sudo apt-get install -y "containerd=$RUNTIME_DEB"
containerd --version
sudo install -d /etc/containerd
containerd config default | sudo tee /etc/containerd/config.toml >/dev/null
sudo sed -i 's/SystemdCgroup = false/SystemdCgroup = true/g' /etc/containerd/config.toml
sudo systemctl enable --now containerd
sudo systemctl restart containerd
sudo systemctl is-active containerd
sudo ctr plugins ls
sudo containerd config dump | grep -A 3 -B 3 SystemdCgroup
```

Estes passos são para um runtime novo e substituem sua configuração inicial. O curso aceita containerd 1.7 ou 2.x fornecido pela distribuição. No 1.x, a configuração CRI fica sob `io.containerd.grpc.v1.cri`; no 2.x, as tabelas mudam, por isso geramos os defaults do binário instalado. Confirme `SystemdCgroup = true` e plugins CRI em `ok`; `cri` não pode estar em `disabled_plugins`. Kubelet e runtime devem usar o gerenciador de cgroups `systemd` neste host. Cgroups são os mecanismos do kernel que contabilizam e limitam recursos; escolher o mesmo gerenciador evita que kubelet e runtime organizem esses recursos de modos conflitantes.

Se o pacote disponível tiver outra versão principal ou o campo não existir, o ambiente saiu da base suportada por esta edição. Pare nessa verificação e use uma imagem/repositório Ubuntu com uma das linhas previstas; adaptar outra linha é um trabalho de manutenção do curso, não uma pesquisa obrigatória do aluno. Capture versão e configuração relevante sem credenciais para a evidência do módulo.

## 3. Instalar kubeadm, kubelet e kubectl com versão explícita

**TODOS OS HOSTS.** O repositório é por versão minor. Prepará-lo não atualiza automaticamente o cluster.

```bash
sudo install -d -m 0755 /etc/apt/keyrings
curl -fsSL https://pkgs.k8s.io/core:/stable:/v1.35/deb/Release.key | sudo gpg --dearmor -o /etc/apt/keyrings/kubernetes-apt-keyring.gpg
printf '%s\n' 'deb [signed-by=/etc/apt/keyrings/kubernetes-apt-keyring.gpg] https://pkgs.k8s.io/core:/stable:/v1.35/deb/ /' | sudo tee /etc/apt/sources.list.d/kubernetes.list
sudo apt-get update
apt-cache madison kubeadm
```

**HOST CP — escolha uma versão patch 1.35 publicada**, copiando a string completa exibida pelo apt, inclusive o sufixo Debian. Anote-a; **HOST WORKER — use a mesma string escolhida no CP**, mesmo se um patch mais recente aparecer entre as instalações.

```bash
read -r -p 'Versão exata 1.35.x do pacote (incluindo sufixo Debian): ' K8S_DEB
[[ "$K8S_DEB" =~ ^1\.35\.[0-9]+- ]] || { printf 'Seleção inválida; escolha novamente.\n'; exit 1; }
sudo apt-get install -y "kubelet=$K8S_DEB" "kubeadm=$K8S_DEB" "kubectl=$K8S_DEB"
sudo apt-mark hold kubelet kubeadm kubectl
sudo systemctl enable kubelet
kubeadm version -o short
kubectl version --client
sudo crictl --runtime-endpoint unix:///run/containerd/containerd.sock info
```

Antes do init/join, kubelet reiniciando e runtime indicando `NetworkReady=false` por falta de CNI são esperados. CRI inacessível não é esperado. Para diagnosticá-lo, use `sudo journalctl -u containerd -n 80 --no-pager`. Registre a versão Debian exata e a versão de Kubernetes resultante; não substitua 1.35 por `latest` ao repetir.

### Instalar também o cliente LOCAL, antes de usá-lo

O kubectl instalado nos servidores não instala nada na estação. **LOCAL — Linux AMD64 ou ARM64:** informe a versão `v1.35.x` mostrada por `kubeadm version -o short` no CP, sem o sufixo Debian. Este cliente fica em uma pasta exclusiva do curso, sem substituir um kubectl usado na produção. O download e seu SHA256 devem ser da mesma versão e arquitetura.

```bash
read -r -p 'Versão registrada no CP, no formato v1.35.x: ' KUBECTL_VERSION
[[ "$KUBECTL_VERSION" =~ ^v1\.35\.[0-9]+$ ]] || { printf 'Versão inválida.\n'; exit 1; }
case "$(uname -m)" in
  x86_64) KUBECTL_ARCH=amd64 ;;
  aarch64|arm64) KUBECTL_ARCH=arm64 ;;
  *) printf 'Arquitetura fora deste roteiro.\n'; exit 1 ;;
esac
KUBECTL_DIR=$(mktemp -d)
curl -fL "https://dl.k8s.io/release/${KUBECTL_VERSION}/bin/linux/${KUBECTL_ARCH}/kubectl" -o "$KUBECTL_DIR/kubectl" || exit 1
curl -fL "https://dl.k8s.io/release/${KUBECTL_VERSION}/bin/linux/${KUBECTL_ARCH}/kubectl.sha256" -o "$KUBECTL_DIR/kubectl.sha256" || exit 1
(cd "$KUBECTL_DIR" && printf '%s  kubectl\n' "$(cat kubectl.sha256)" | sha256sum --check) || exit 1
install -d -m 700 "$HOME/.local/curso-kubernetes/bin"
install -m 755 "$KUBECTL_DIR/kubectl" "$HOME/.local/curso-kubernetes/bin/kubectl"
export PATH="$HOME/.local/curso-kubernetes/bin:$PATH"
command -v kubectl
kubectl version --client
```

Só prossiga após `kubectl: OK` e a versão esperada. `--client` não exige cluster. Em cada novo terminal do curso, repita o `export PATH` acima antes de escolher o kubeconfig; confira `command -v kubectl` para evitar usar por engano outro cliente instalado. A escolha de arquitetura é da estação, não da EC2.

## 4. Inicializar apenas cp1

**HOST CP.** Use os endereços decididos e confirme que a interface realmente possui `10.42.10.10` antes do init. Esses valores serão reutilizados no Calico e não devem ser trocados por CIDRs genéricos.

```bash
CP_IP=10.42.10.10
POD_CIDR=172.20.0.0/16
SERVICE_CIDR=10.96.0.0/12
ip -br address | grep -F "$CP_IP"
getent hosts lab-k8s.internal
K8S_VERSION=$(kubeadm version -o short)
sudo kubeadm config images pull --kubernetes-version "$K8S_VERSION" --cri-socket unix:///run/containerd/containerd.sock
sudo kubeadm init --kubernetes-version "$K8S_VERSION" --control-plane-endpoint lab-k8s.internal:6443 --apiserver-advertise-address "$CP_IP" --pod-network-cidr "$POD_CIDR" --service-cidr "$SERVICE_CIDR" --node-name cp1 --cri-socket unix:///run/containerd/containerd.sock
```

Pare se o init falhar: não rode-o em loop nem use `--ignore-preflight-errors=all`. Examine a primeira falha, os logs do kubelet e os containers CRI. O comando `join` exibido contém uma credencial temporária; mantenha-o fora do Git e de capturas públicas.

Configure o acesso do usuário SSH no CP; este arquivo é uma credencial administrativa:

```bash
# HOST CP — como usuário normal com sudo, não como root
install -d -m 700 "$HOME/.kube"
sudo install -o "$(id -u)" -g "$(id -g)" -m 600 /etc/kubernetes/admin.conf "$HOME/.kube/config"
kubectl get --raw='/readyz?verbose'
kubectl get nodes
kubectl get pods -n kube-system -o wide
sudo ls -l /etc/kubernetes/manifests
sudo grep cgroupDriver /var/lib/kubelet/config.yaml
```

`cp1` ainda pode estar `NotReady` e CoreDNS pendente sem CNI. Identifique os quatro static Pods e associe cada um a seu YAML local. Nunca guarde backups de manifests dentro de `/etc/kubernetes/manifests`: o kubelet pode tentar interpretá-los também.

**LOCAL — copiar o kubeconfig por chave temporária e manter um túnel para a API.** A estação não tem rota direta até a VPC. Abra um segundo terminal para o túnel SSH da cópia e deixe-o em primeiro plano:

```bash
# LOCAL, terminal TUNEL-COPIA
source .env.m01-aws
aws ec2-instance-connect open-tunnel \
  --region "$AWS_REGION" \
  --instance-id "$CP_INSTANCE_ID" \
  --instance-connect-endpoint-id "$EICE_ID" \
  --remote-port 22 \
  --local-port 2222 \
  --max-tunnel-duration 3600
```

No CP, registre a fingerprint com `sudo ssh-keygen -lf /etc/ssh/ssh_host_ed25519_key.pub`. Em outro terminal LOCAL, gere uma chave descartável, publique-a e faça a cópia em até 60 segundos. Ao primeiro acesso a `[127.0.0.1]:2222`, só aceite a host key se a fingerprint for igual à registrada no CP.

```bash
# LOCAL, terminal principal
source .env.m01-aws
install -d -m 700 "$HOME/.kube"
test ! -e "$HOME/.kube/curso-kubeconfig" || { printf 'O destino já existe; identifique-o antes de continuar.\n'; exit 1; }
EICE_KEY_DIR=$(mktemp -d)
chmod 700 "$EICE_KEY_DIR"
ssh-keygen -q -t ed25519 -N '' -f "$EICE_KEY_DIR/id_ed25519"
aws ec2-instance-connect send-ssh-public-key \
  --region "$AWS_REGION" \
  --instance-id "$CP_INSTANCE_ID" \
  --availability-zone "$LAB_AZ" \
  --instance-os-user ubuntu \
  --ssh-public-key "file://$EICE_KEY_DIR/id_ed25519.pub"
scp -P 2222 -i "$EICE_KEY_DIR/id_ed25519" -o IdentitiesOnly=yes \
  ubuntu@127.0.0.1:.kube/config "$HOME/.kube/curso-kubeconfig"
chmod 600 "$HOME/.kube/curso-kubeconfig"
rm -f "$EICE_KEY_DIR/id_ed25519" "$EICE_KEY_DIR/id_ed25519.pub"
rmdir "$EICE_KEY_DIR"
```

Encerre `TUNEL-COPIA` com Ctrl+C. Use `sudoedit /etc/hosts` em LOCAL e associe `127.0.0.1 lab-k8s.internal`. Então abra um terminal exclusivo e deixe o encaminhamento da API ativo durante a prática:

```bash
# LOCAL, terminal TUNEL-API
source .env.m01-aws
aws ec2-instance-connect ssh \
  --region "$AWS_REGION" \
  --instance-id "$CP_INSTANCE_ID" \
  --os-user ubuntu \
  --connection-type eice \
  --eice-options "endpointId=$EICE_ID,maxTunnelDuration=3600" \
  --local-forwarding 6443:127.0.0.1:6443
```

No terminal principal, selecione o arquivo copiado e valide o alvo. Se o túnel expirar ou for fechado, reabra-o; a identidade IAM autoriza uma nova sessão, e o kubeconfig não precisa mudar.

```bash
export KUBECONFIG="$HOME/.kube/curso-kubeconfig"
kubectl config rename-context kubernetes-admin@kubernetes curso-kubeadm
kubectl config current-context
kubectl config view --minify
kubectl cluster-info
```

Exporte `KUBECONFIG` em cada terminal LOCAL usado no curso. Um contexto reúne endpoint, identidade e namespace; renomeá-lo muda apenas o nome local, não o cluster. Para conferir o alvo use `kubectl config current-context`, `kubectl config view --minify` e `kubectl get nodes -o wide`. A saída sem `--raw` oculta material sensível, mas ainda precisa de revisão antes de publicação.

Daqui em diante, `get` consulta objetos; `describe` reúne condições e eventos; `logs` lê a saída dos containers; `wait` aguarda uma condição com limite de tempo. `create -f` cria objetos a partir de um arquivo e avisa se já existem; `apply -f` cria ou atualiza a configuração declarada. `-n` escolhe namespace e `-A` lista todos. Essas operações devem sempre atingir o contexto do curso.

## 5. Instalar CNI e adicionar workers

**LOCAL.** Calico 3.32 suporta Kubernetes 1.35 e a arquitetura AMD64 deste laboratório. Usaremos o operador e CRDs `crd.projectcalico.org/v1`, sem a migração opcional para CRDs v3 nativas que exigiria configuração adicional no Kubernetes 1.35. O operador também tem seus recursos `operator.tigera.io/v1`.

Uma **CRD** registra um novo tipo de objeto na API, incluindo seus campos. Ela não é um processo executando. Um **operator** é um controller que usa esses objetos para operar um componente. Aqui a CRD permite registrar uma `Installation`; o operador interpreta essa configuração e mantém o Calico. Não é necessário escrever CRDs ou controllers para instalar a primeira aplicação.

Os dois downloads abaixo são manifests do fornecedor com versão fixa, não leituras conceituais. No `less`, procure `kind: Deployment`, `kind: ClusterRole` e `kind: ServiceAccount` para identificar processo e permissões do operador, depois saia com `q`. Não é necessário estudar cada campo de todas as CRDs. A aplicação cria recursos com alcance de cluster e deve ocorrer apenas no laboratório.

```bash
curl -fL -o /tmp/calico-v1-crds-3.32.2.yaml https://raw.githubusercontent.com/projectcalico/calico/v3.32.2/manifests/v1_crd_projectcalico_org.yaml
curl -fL -o /tmp/tigera-operator-3.32.2.yaml https://raw.githubusercontent.com/projectcalico/calico/v3.32.2/manifests/tigera-operator.yaml
less /tmp/tigera-operator-3.32.2.yaml
kubectl create -f /tmp/calico-v1-crds-3.32.2.yaml
kubectl create -f /tmp/tigera-operator-3.32.2.yaml
kubectl wait --for=condition=Established crd/installations.operator.tigera.io --timeout=120s
```

Crie **LOCAL** um arquivo de configuração do seu laboratório, `calico-installation.yaml`, com seu editor. O `cidr` abaixo é exatamente o `POD_CIDR` do init. O conteúdo escolhe encapsulamento inclusive dentro da subnet; isso simplifica o primeiro laboratório AWS sem depender de rotas para cada Pod IP.

```yaml
apiVersion: operator.tigera.io/v1
kind: Installation
metadata:
  name: default
spec:
  calicoNetwork:
    linuxDataplane: Iptables
    bgp: Disabled
    ipPools:
      - name: default-ipv4-ippool
        blockSize: 26
        cidr: 172.20.0.0/16
        encapsulation: VXLAN
        natOutgoing: Enabled
        nodeSelector: all()
```

```bash
# LOCAL
kubectl apply -f calico-installation.yaml
kubectl get pods -n tigera-operator
kubectl get pods -n calico-system -o wide
# HOST CP — gere join válido por apenas 30 minutos
sudo kubeadm token create --ttl 30m --print-join-command
```

**HOST WORKER — em cada worker preparado**, execute o comando completo que o CP gerou, prefixado por `sudo`, e acrescente `--cri-socket unix:///run/containerd/containerd.sock`. Não invente nem omita o `--discovery-token-ca-cert-hash`; ele verifica a CA descoberta. A opção `--control-plane` não deve aparecer no join destes workers. Se o token expirar, gere outro no CP.

```bash
# LOCAL — após os dois joins
kubectl wait --for=condition=Ready node/cp1 node/worker1 node/worker2 --timeout=300s
kubectl get nodes -o wide
kubectl get pods -A -o wide
kubectl get tigerastatus
kubectl rollout status deployment/coredns -n kube-system --timeout=180s
kubectl get node cp1 -o jsonpath='{.spec.taints}'
```

Preserve o taint do control plane. Com os workers presentes, os componentes que precisarem de scheduling poderão convergir. Se o Calico estiver degradado, olhe primeiro o operador, depois calico-node/Typha, e verifique endpoint da API, IPs detectados, CIDR e portas privadas. Não instale um segundo CNI para tentar corrigir o primeiro.

## 6. Provar a rede antes de encerrar a instalação

`Ready` do nó não prova toda a rede. O arquivo [rede.yaml](../laboratorios/01-control-plane/rede.yaml) cria o namespace temporário `curso-rede-inicial` e dois Pods de teste. Cada um executa um servidor BusyBox não root que publica seu nome em HTTP 8080. `nodeSelector` exige a label de hostname do worker correspondente; usamos esse campo apenas para garantir que o teste atravessa dois nós. O módulo 05 aprofundará posicionamento. Confirme as labels antes de aplicar; se os nomes forem diferentes, ajuste somente os dois seletores do arquivo.

```bash
# LOCAL — na raiz do repositório
kubectl get nodes -L kubernetes.io/hostname
kubectl apply -f laboratorios/01-control-plane/rede.yaml
kubectl wait -n curso-rede-inicial --for=condition=Ready pod/rede-worker1 pod/rede-worker2 --timeout=180s
kubectl get pods -n curso-rede-inicial -o wide
REDE_IP_1=$(kubectl get pod rede-worker1 -n curso-rede-inicial -o jsonpath='{.status.podIP}')
REDE_IP_2=$(kubectl get pod rede-worker2 -n curso-rede-inicial -o jsonpath='{.status.podIP}')
kubectl exec -n curso-rede-inicial rede-worker1 -- wget -T 5 -qO- "http://${REDE_IP_2}:8080/"
kubectl exec -n curso-rede-inicial rede-worker2 -- wget -T 5 -qO- "http://${REDE_IP_1}:8080/"
kubectl exec -n curso-rede-inicial rede-worker1 -- nslookup kubernetes.default.svc.cluster.local
kubectl exec -n curso-rede-inicial rede-worker2 -- nslookup kubernetes.default.svc.cluster.local
```

**Resultado esperado:** Pods em workers distintos, HTTP retornando o nome do Pod remoto nas duas direções e DNS resolvendo o Service da API nos dois Pods. `exec` executa o cliente dentro do Pod; portanto o tráfego HTTP passa pela rede de Pods, não pelo túnel de `port-forward`. Isso valida um caminho concreto, não todos os tamanhos de pacote e protocolos possíveis.

Se os Pods estiverem Pending, examine `kubectl describe pod -n curso-rede-inicial rede-worker1` e o equivalente do segundo: compare seletor, label e recursos disponíveis. Se houver falha de imagem, confira saída HTTPS/registry. Se estiverem Running mas o HTTP falhar, examine logs dos Pods e Calico, UDP 4789 entre os nós e CIDRs. Se apenas o DNS falhar, veja `kubectl get pods,service -n kube-system` e `kubectl logs -n kube-system deployment/coredns --tail=80`.

Guarde as saídas curtas e remova somente os recursos de teste com `kubectl delete -f laboratorios/01-control-plane/rede.yaml`. Isso elimina também seu namespace e arquivos temporários; não há dado persistente a recuperar nesse teste.

## Evidência, falha e recuperação

**Sucesso:** três Nodes `Ready`, versão igual à registrada, CoreDNS disponível, Calico sem degradação, API `/readyz` aprovada e o teste HTTP/DNS acima concluído. Explique por que `/var/lib/etcd` contém estado do cluster e não os uploads da aplicação.

**Falha guiada — HOST WORKER worker2, 10 minutos:** confirme que é o worker de laboratório e execute `sudo systemctl stop kubelet`. **LOCAL:** observe `kubectl get nodes -w` e `kubectl describe node worker2`. Registre quanto demora até a condição mudar; isso depende de heartbeats e tolerâncias, não é instantâneo. Containers existentes podem continuar rodando porque kubelet e runtime são processos diferentes.

**Recuperação — HOST WORKER worker2:** `sudo systemctl start kubelet`; examine `sudo journalctl -u kubelet -n 80 --no-pager`. **LOCAL:** aguarde `kubectl wait --for=condition=Ready node/worker2 --timeout=180s` e confirme a API saudável. Não use reset para recuperar um serviço parado.

**Exercício autônomo, 60–90 minutos:** escreva a sequência para preparar um worker novo, sem copiar os blocos, usando sua lista de decisões e a ajuda pontual dos comandos. Inclua runtime/cgroups, versão exata, endpoint, token, hash da CA e verificações de sucesso. Compare seu runbook com as etapas da aula e corrija omissões justificando o risco de cada uma. Essa revisão do procedimento é a entrega obrigatória; a execução independente faz parte da dimensão de prática a repetir.

**Extensão prática com custo:** se houver orçamento para uma quarta máquina temporária, execute o runbook, faça o nó ingressar e prove arquitetura, versão e Ready. Não substitua worker2 nem termine um nó em uso para economizar: drain e remoção segura serão ensinados no módulo 05. Registre a máquina adicional no inventário até sua remoção consciente. Sem essa execução, registre a reconstrução como ensaio de procedimento, não como cluster recriado.

**Rubrica, 10 pontos:** 2 para VPC, tags, inventário e acesso privado explicados; 2 para componentes e static Pods; 2 para versão/runtime/cgroups corretos; 2 para rede e recuperação do kubelet; 2 para evidências, runbook e destruição comprovada. Avance com 8/10, recuperação demonstrada e nenhum recurso cobrado remanescente.

## 7. Destruir manualmente o laboratório

A destruição faz parte do exercício. Primeiro salve as evidências sem kubeconfig, tokens ou chaves; depois encerre os túneis. Não use o filtro de tags como autorização para apagar em massa: os IDs registrados em `.env.m01-aws` definem o alvo, e `LabRun` serve para confirmar que todos pertencem à mesma execução.

**LOCAL — confira conta, execução, tags e volumes antes de qualquer exclusão:**

```bash
source .env.m01-aws
CURRENT_ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)
[[ "$CURRENT_ACCOUNT_ID" == "$AWS_ACCOUNT_ID" ]] || { printf 'Conta diferente da criação.\n'; exit 1; }

aws ec2 describe-instances \
  --region "$AWS_REGION" \
  --instance-ids "$CP_INSTANCE_ID" "$WORKER1_INSTANCE_ID" "$WORKER2_INSTANCE_ID" \
  --query 'Reservations[].Instances[].{id:InstanceId,estado:State.Name,vpc:VpcId,nome:Tags[?Key==`Name`]|[0].Value,run:Tags[?Key==`LabRun`]|[0].Value,volumes:BlockDeviceMappings[].{id:Ebs.VolumeId,apagaComInstancia:Ebs.DeleteOnTermination}}' \
  --output table
aws resourcegroupstaggingapi get-resources \
  --region "$AWS_REGION" \
  --tag-filters "Key=LabRun,Values=$LAB_RUN" \
  --query 'ResourceTagMappingList[].ResourceARN' \
  --output table

read -r -p "Digite exatamente $LAB_RUN para confirmar a destruição: " CONFIRM_LAB_RUN
[[ "$CONFIRM_LAB_RUN" == "$LAB_RUN" ]] || { printf 'Confirmação divergente.\n'; exit 1; }
```

A tabela precisa mostrar os três IDs esperados, o mesmo VPC e `apagaComInstancia=true` nos EBS raiz. Se aparecer outro `LabRun`, pare e investigue. Então exclua em ordem de dependência:

```bash
aws ec2 terminate-instances \
  --region "$AWS_REGION" \
  --instance-ids "$CP_INSTANCE_ID" "$WORKER1_INSTANCE_ID" "$WORKER2_INSTANCE_ID"
aws ec2 wait instance-terminated \
  --region "$AWS_REGION" \
  --instance-ids "$CP_INSTANCE_ID" "$WORKER1_INSTANCE_ID" "$WORKER2_INSTANCE_ID"

aws ec2 delete-instance-connect-endpoint \
  --region "$AWS_REGION" \
  --instance-connect-endpoint-id "$EICE_ID"
for ATTEMPT in {1..60}; do
  if ! EICE_STATE=$(aws ec2 describe-instance-connect-endpoints \
    --region "$AWS_REGION" \
    --instance-connect-endpoint-ids "$EICE_ID" \
    --query 'InstanceConnectEndpoints[0].State' --output text 2>/dev/null); then
    break
  fi
  printf 'Remoção do EICE: %s\n' "$EICE_STATE"
  [[ "$EICE_STATE" == delete-complete || "$EICE_STATE" == None ]] && break
  sleep 5
done

aws ec2 delete-security-group --region "$AWS_REGION" --group-id "$EICE_SG_ID"
aws ec2 delete-security-group --region "$AWS_REGION" --group-id "$NODE_SG_ID"
aws ec2 disassociate-route-table --region "$AWS_REGION" --association-id "$ROUTE_ASSOCIATION_ID"
aws ec2 delete-route-table --region "$AWS_REGION" --route-table-id "$ROUTE_TABLE_ID"
aws ec2 detach-internet-gateway --region "$AWS_REGION" --internet-gateway-id "$IGW_ID" --vpc-id "$VPC_ID"
aws ec2 delete-internet-gateway --region "$AWS_REGION" --internet-gateway-id "$IGW_ID"
aws ec2 delete-subnet --region "$AWS_REGION" --subnet-id "$SUBNET_ID"
aws ec2 delete-vpc --region "$AWS_REGION" --vpc-id "$VPC_ID"
```

A remoção da VPC também elimina os recursos padrão que a AWS criou com ela. Não prossiga cegamente se surgir `DependencyViolation`: consulte ENIs, endpoints, SGs e associações da VPC, relacione o achado aos IDs registrados e remova somente a dependência desta execução.

Faça a verificação final por serviço. Instâncias terminadas podem continuar visíveis no histórico por algum tempo, mas devem estar `terminated` e sem IPv4 público; as outras consultas devem ficar vazias após a convergência:

```bash
aws ec2 describe-instances \
  --region "$AWS_REGION" \
  --instance-ids "$CP_INSTANCE_ID" "$WORKER1_INSTANCE_ID" "$WORKER2_INSTANCE_ID" \
  --query 'Reservations[].Instances[].{id:InstanceId,estado:State.Name,publico:PublicIpAddress}' \
  --output table
aws ec2 describe-volumes \
  --region "$AWS_REGION" \
  --filters "Name=tag:LabRun,Values=$LAB_RUN" \
  --query 'Volumes[].{id:VolumeId,estado:State,tamanho:Size}' \
  --output table
aws ec2 describe-network-interfaces \
  --region "$AWS_REGION" \
  --filters "Name=tag:LabRun,Values=$LAB_RUN" \
  --query 'NetworkInterfaces[].{id:NetworkInterfaceId,status:Status}' \
  --output table
aws ec2 describe-vpcs \
  --region "$AWS_REGION" \
  --filters "Name=tag:LabRun,Values=$LAB_RUN" \
  --query 'Vpcs[].VpcId' \
  --output table
```

Revise também EC2, EBS, VPC e Public IPv4 Insights no console da região. No dia seguinte, filtre o Cost Explorer por `LabRun` e `Modulo=m01`, lembrando que dados de custo não são instantâneos. Só depois dessa confirmação remova `.env.m01-aws` e o kubeconfig local com `rm -f .env.m01-aws "$HOME/.kube/curso-kubeconfig"`, além das linhas adicionadas a `/etc/hosts`.

Preserve o orçamento da conta, a identidade IAM, a ativação das cost allocation tags, o repositório e as evidências: são controles e artefatos reutilizáveis, não infraestrutura desta execução. O que deve chegar a zero é o conjunto dos IDs registrados; `LabRun` ajuda apenas a detectar resíduos da mesma execução.

### Fronteira da automação depois desta aula

Após concluir e destruir esta primeira execução, a reconstrução para os módulos seguintes poderá usar o [Terraform de apoio](../laboratorios/01-control-plane/terraform/README.md). Ele cria a mesma rede e os três hosts, prepara os requisitos, inicializa cp1 e instala o CNI. A fronteira manual começa ao gerar um token temporário no CP, executar o join nos workers e restaurar os objetos Kubernetes necessários. Terraform não substitui nenhuma evidência nem pontuação deste módulo.

## Fechamento

Você passou de máquinas Linux a um cluster cuja API recebe intenções e cujos agentes executam e reportam o resultado. Kubeadm instalou o control plane; kubelet mantém os static Pods; containerd executa containers; Calico e CoreDNS permitem comunicação e descoberta. Parar kubelet não equivale a desligar o runtime, e aceitar um manifest não equivale a concluir a reconciliação.

Explique sem consultar: quem decide o nó de um Pod? Quem mantém o API Server se o scheduler parar? Por que o disco de etcd não é storage de uploads? Que teste demonstrou comunicação entre workers? Se uma resposta falhar, retome a seção correspondente, não a instalação inteira.

Avance com a rubrica atingida, o kubelet recuperado, as evidências de API, runtime, rede e versões e a destruição confirmada. Quando iniciar a próxima prática, a infraestrutura de apoio poderá reconstruir a base; você continuará responsável pelo join e pelo estado Kubernetes. Aplicações, PVCs, HA e recuperação de etcd ainda não foram ensinados. Próximo: [02 — Workloads e reconciliação](02-workloads.md).

## Referências opcionais

O procedimento necessário termina acima. As fontes aprofundam alternativas e detalhes, sem exigir leitura adicional para concluir. Base Kubernetes consultada em 10/09/2026; cliente Linux e NetworkManager reconferidos em 12/09/2026; AWS, acesso e tags reconferidos em 15/09/2026.

- [EC2 no Free Tier](https://docs.aws.amazon.com/AWSEC2/latest/UserGuide/ec2-free-tier-usage.html) — diferenças entre planos, elegibilidade e forma de consulta.
- [EC2 Instance Connect Endpoint](https://docs.aws.amazon.com/AWSEC2/latest/UserGuide/create-ec2-instance-connect-endpoints.html) e [Security Groups do endpoint](https://docs.aws.amazon.com/AWSEC2/latest/UserGuide/eice-security-groups.html) — comportamento do endpoint e alternativas de controle.
- [Cost allocation tags](https://docs.aws.amazon.com/awsaccountbilling/latest/aboutv2/cost-alloc-tags.html) e [boas práticas de tags](https://docs.aws.amazon.com/tag-editor/latest/userguide/best-practices-and-strats.html) — ativação para relatórios e desenho de uma taxonomia maior.
- [Componentes](https://kubernetes.io/docs/concepts/overview/components/) e [controllers](https://kubernetes.io/docs/concepts/architecture/controller/) — responsabilidades e exemplos além do fluxo introdutório.
- [Static Pods](https://kubernetes.io/docs/tasks/configure-pod-container/static-pod/) — limitações e configuração fora do padrão gerado pelo kubeadm.
- [Criar cluster com kubeadm](https://kubernetes.io/docs/setup/production-environment/tools/kubeadm/create-cluster-kubeadm/) — opções de inicialização e topologias diferentes da adotada.
- [Portas e protocolos](https://kubernetes.io/docs/reference/networking/ports-and-protocols/) — inventário geral para planejar configurações que vão além deste firewall.
- [Container runtimes](https://kubernetes.io/docs/setup/production-environment/container-runtimes/#containerd) — diferenças entre implementações e versões de configuração.
- [Instalar kubeadm](https://kubernetes.io/docs/setup/production-environment/tools/kubeadm/install-kubeadm/) e [kubectl em Linux](https://kubernetes.io/docs/tasks/tools/install-kubectl-linux/) — métodos alternativos aos procedimentos completos desta aula.
- [Requisitos do Calico](https://docs.tigera.io/calico/latest/getting-started/kubernetes/requirements) e [NetworkManager](https://docs.tigera.io/calico/latest/operations/troubleshoot/troubleshooting#configure-networkmanager) — matrizes e detalhes para adaptar outro ambiente.
- [Calico self-managed](https://docs.tigera.io/calico/latest/getting-started/kubernetes/self-managed-onprem/onpremises) — outras opções de instalação, fora do caminho VXLAN desta aula.
