# Infraestrutura descartável do módulo 01

Este Terraform só entra na rota principal **depois** que a primeira construção e a
primeira destruição manuais do módulo 01 forem aprovadas. Ele existe para reconstruir
com baixo atrito a base dos módulos seguintes; não é objetivo nem atalho de avaliação
da primeira aula.

A configuração cria em `us-east-1` a mesma VPC do exercício, três EC2 Ubuntu 24.04
AMD64 `c7i-flex.large` com 30 GiB gp3 e acesso por EC2 Instance Connect Endpoint. Os
nodes recebem IPv4 público temporário somente para saída; nenhum SG aceita conexões
administrativas da Internet. Não há NAT Gateway, load balancer, EIP ou Hosted Zone.

Há dois modos:

- `bootstrap_control_plane = true` é o padrão das reconstruções: prepara os três
  hosts, inicializa `cp1` e aplica Calico. `worker1` e `worker2` ficam preparados,
  mas o token e os joins continuam manuais.
- `bootstrap_control_plane = false` entrega três Ubuntu limpos para uma repetição
  opcional da instalação inteira ou para troubleshooting da automação.

Mudar o modo altera `user_data` e substitui as instâncias. Este laboratório não deve
ser usado para produção.

## Preparar e revisar

Use Terraform 1.6 ou superior e AWS CLI v2 autenticada na conta de laboratório.
Confira a região, os CIDRs e o teto de gasto antes do apply. Edite também `owner`,
`module_id`, `lab_run` e `expires_on` em `terraform.tfvars`. Use um `LabRun`
imutável novo a cada apply, no formato `run-AAAAMMDDThhmmssZ`; `ExpiresOn` é
informativo e não agenda o destroy. `Modulo` registra apenas o contexto de estudo da
sessão: ele pode mudar e nunca deve selecionar, autorizar ou excluir recursos.
O provider aplica `Projeto`, `Ambiente`, `Modulo`, `ClusterName`, `Owner`,
`CostCenter`, `ManagedBy=terraform`, `LabRun` e `ExpiresOn` a todos os recursos
compatíveis. O `Name` segue `kubelab-${lab_run}-${componente}`, igual ao modo
manual; por exemplo, `kubelab-run-20260915T120000Z-cp1`.

> **Plano da conta:** `c7i-flex.large` oferece 2 vCPU e 4 GiB em AMD64 e está
> marcado como elegível no Free Tier atual. Elegibilidade, disponibilidade e
> créditos podem variar por conta, região e data; confirme-os antes de cada janela.

Confirme o plano e o tipo antes de criar recursos:

```bash
aws freetier get-account-plan-state \
  --region us-east-1 \
  --query '{plano:accountPlanType,status:accountPlanStatus}'
aws ec2 describe-instance-types --region us-east-1 --instance-types c7i-flex.large --query 'InstanceTypes[0].{tipo:InstanceType,vcpus:VCpuInfo.DefaultVCpus,memoriaMiB:MemoryInfo.SizeInMiB,elegivel:FreeTierEligible,arquitetura:ProcessorInfo.SupportedArchitectures}'
```

```bash
cd laboratorios/01-control-plane/terraform
cp terraform.tfvars.example terraform.tfvars
terraform init
terraform fmt -check
terraform validate
terraform plan -out=criar.tfplan
terraform show criar.tfplan
terraform apply criar.tfplan
```

`terraform apply` termina quando a AWS criou as EC2; cloud-init ainda pode estar
instalando pacotes e inicializando o CP. Aguarde a fronteira operacional:

```bash
./aguardar-bootstrap.sh
terraform output ssh_commands
terraform output manual_handoff
```

A AMI consultada pelo parâmetro público da Canonical pode mudar no futuro. Registre
`terraform output -raw ubuntu_ami_id` e fixe o resultado em `terraform.tfvars` antes
de comparar duas reconstruções.

## Retomar na fronteira manual

Copie o comando `cp1` exibido em `ssh_commands`. Dentro do CP:

```bash
sudo cloud-init status --wait
sudo test -f /var/lib/curso-bootstrap/control-plane-ready
kubectl get --raw='/readyz'
sudo kubeadm token create --ttl 30m --print-join-command
```

O último comando é credencial temporária: não o registre no Git, no logbook ou em
capturas. Entre em cada worker pelo respectivo comando de `ssh_commands`. Aguarde
`sudo cloud-init status --wait` e confirme
`sudo test -f /var/lib/curso-bootstrap/host-prepared`. Só então execute o
join com `sudo`, acrescentando:

```text
--cri-socket unix:///run/containerd/containerd.sock
```

Após os dois ingressos, volte ao CP e valide Nodes, CoreDNS e Calico conforme a aula.
Gerar o token, ingressar os workers e restaurar os recursos Kubernetes são tarefas
manuais; nenhum token ou kubeconfig é armazenado no state Terraform.

## Repetição opcional com hosts limpos

Se quiser repetir integralmente a instalação depois da primeira aprovação, use
`bootstrap_control_plane = false`. Esse modo não é o caminho normal entre módulos e
não altera a fronteira automatizada definida acima. Como uma reconstrução cria novas
host keys, compare as fingerprints com cada host novo e remova somente a entrada
obsoleta que o cliente SSH indicar; nunca desative a verificação para esconder uma
divergência inesperada.

Os arquivos internos de bootstrap são implementação da automação, não gabarito da
prática manual. O critério de sucesso continua sendo o estado observado no cluster.

## Destruir conscientemente

```bash
terraform plan -destroy -out=destruir.tfplan
terraform show destruir.tfplan
terraform apply destruir.tfplan
terraform state list
```

Espere `terraform state list` vazio. Depois confira no inventário AWS, pelos IDs do
state e pelo `LabRun`, que não restaram instâncias, EBS, IPv4 públicos ou EC2
Instance Connect Endpoint do laboratório. `Modulo` serve apenas para agrupar a
revisão financeira; ele nunca identifica o alvo do destroy. Nenhuma tag, isoladamente,
autoriza exclusão. Revise o Cost Explorer novamente quando os dados da sessão tiverem
convergido.
