# 01 — Construir e compreender o control plane

**Duração:** 16–22 horas, incluindo reconstrução e diagnóstico. **Pré-requisitos:** módulo 00; três máquinas novas Ubuntu 24.04, SSH/sudo e acesso à rede privada. **Entrega:** um CP e dois workers `Ready`, API acessível por nome estável, tráfego entre pods e um registro que explique cada componente. Não execute estes preparativos em hosts do Swarm existente.

## O que acontece ao pedir um Deployment

`kubectl` envia um objeto ao API Server. A API autentica, autoriza, valida e persiste o estado no etcd. O controller de Deployment mantém ReplicaSets; o de ReplicaSet mantém Pods. O scheduler associa cada Pod ainda sem nó a um Node adequado. O kubelet daquele nó pede ao runtime que prepare o sandbox e os containers; a integração CNI configura a rede. Os componentes observam a API e reconciliam continuamente. O API Server não executa seu container e o scheduler não copia imagens. [Componentes](https://kubernetes.io/docs/concepts/overview/components/) e [reconciliação](https://kubernetes.io/docs/concepts/architecture/controller/).

`kubeadm` prepara o cluster e seus certificados; `kubelet` é o agente de cada nó; `kubectl` é um cliente da API. Neste laboratório, API Server, scheduler, controller-manager e etcd são **static Pods**: o kubelet os mantém a partir de arquivos locais. Os objetos vistos pela API são seus mirror Pods. Isso permite iniciar o próprio control plane antes de haver scheduler funcional. [Static Pods](https://kubernetes.io/docs/tasks/configure-pod-container/static-pod/).

## Topologia e escolhas antes dos comandos

| Máquina/rede | Base do laboratório | Por quê |
| --- | --- | --- |
| cp1 | 2 vCPU, 4 GiB RAM, 30 GiB gp3 | Folga para sistema, API e etcd; não é sizing universal |
| worker1 e worker2 | 2 vCPU, 4 GiB RAM, 30 GiB gp3 cada | Dois destinos para testar scheduling e rede |
| SO e arquitetura | Ubuntu 24.04 ARM64 | Combina com Graviton e imagens multiarch da trilha |
| Kubernetes | Linha 1.35, patch explicitamente selecionado abaixo | Base didática e de exame desta edição |
| CNI | Calico 3.32.2, VXLAN, BGP desabilitado | Rede entre nós e suporte a NetworkPolicy |
| Endpoint | `lab-k8s.internal:6443` | Nome estável desde o primeiro init, útil na futura HA |

Use uma AZ inicialmente. O EBS raiz da EC2 guarda sistema, containerd e `/var/lib/etcd`; ele existe antes do Kubernetes e não é um PVC. Não há storage de aplicação neste módulo. ARM64 não é exigência do Kubernetes; AMD64 também funciona com pacotes e imagens compatíveis.

Escolha CIDRs que **não se sobreponham** à VPC, VPN, LAN, rede do Swarm ou entre si. A sugestão `192.168.0.0/16` para pods e `10.96.0.0/12` para Services só serve após essa verificação. Se sua LAN usa 192.168.x.x, escolha outro intervalo e use-o de modo consistente no init e no Calico.

Crie no DNS privado o registro `lab-k8s.internal` apontando ao IP privado fixo de cp1. LOCAL e todos os hosts precisam resolver esse nome e alcançar a porta 6443. Para laboratório sem DNS privado, use `sudoedit /etc/hosts` em cada máquina e acrescente `IP_PRIVADO_REAL lab-k8s.internal`; o texto `IP_PRIVADO_REAL` precisa ser substituído. Anote que essa alternativa exigirá atualização em todos os hosts na HA. O nome em `/etc/hosts` não é propagado automaticamente aos pods, que usam CoreDNS; os componentes internos podem acessar `kubernetes.default.svc`.

Um load balancer TCP futuro assumirá esse nome. `--control-plane-endpoint` agora evita construir o acesso ao cluster em torno do endereço de uma única máquina. [Endpoint compartilhado no kubeadm](https://kubernetes.io/docs/setup/production-environment/tools/kubeadm/create-cluster-kubeadm/#initializing-your-control-plane-node).

## Firewall antes da inicialização

Use Security Groups com origens restritas aos SGs dos nós e à VPN/bastion de administração. Confira também rotas e NACLs. A tabela descreve entrada; respostas precisam ser permitidas e NACLs são stateless.

| Destino | Porta/protocolo | Origem autorizada |
| --- | --- | --- |
| Todos os hosts | TCP 22 | Bastion/VPN administrativa |
| CP | TCP 6443 | Nós e cliente administrativo pela rede privada |
| Todos os hosts | TCP 10250 | CP; posteriormente componentes autorizados, como metrics-server |
| Todos os hosts | UDP 4789 | Somente nós do cluster, VXLAN |
| Todos os hosts | TCP 5473 | Somente nós, para Calico Typha |
| CPs futuros | TCP 2379–2380 | Somente outros CPs; não expor etcd aos workers |

Saída deve alcançar DNS autorizado (UDP/TCP 53), fontes de tempo e HTTPS para repositórios/registries. Scheduler/controller-manager usam portas locais; não abra 10257/10259 na Internet. Não abra toda a faixa NodePort agora. As origens inter-node precisam cobrir CP e workers mesmo que estejam em SGs distintos. [Portas Kubernetes](https://kubernetes.io/docs/reference/networking/ports-and-protocols/) e [requisitos Calico](https://docs.tigera.io/calico/latest/getting-started/kubernetes/requirements).

Calico precisa controlar suas interfaces e regras de rede. Em hosts novos deste lab, evite firewalld/UFW concorrendo com ele; mantenha a restrição de perímetro nos SGs. Se NetworkManager estiver presente, configure-o conforme os requisitos Calico para não gerenciar interfaces `cali*`/VXLAN. Não desative um firewall existente sem primeiro validar o acesso e as proteções equivalentes.

## 1. Preparar todos os hosts

**TODOS OS HOSTS — repetir por SSH, conferindo o nome antes de sudo.** Use nomes únicos `cp1`, `worker1` e `worker2`; se necessário, ajuste com `sudo hostnamectl set-hostname NOME_REAL` e reconecte.

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

Estes passos são para um runtime novo e substituem sua configuração inicial. O curso aceita containerd 1.7 ou 2.x fornecido pela distribuição. No 1.x, a configuração CRI fica sob `io.containerd.grpc.v1.cri`; no 2.x, as tabelas mudam, por isso geramos os defaults do binário instalado. Confirme `SystemdCgroup = true` e plugins CRI em `ok`; `cri` não pode estar em `disabled_plugins`. Kubelet e runtime devem usar o gerenciador de cgroups `systemd` neste host. [Runtime e cgroups](https://kubernetes.io/docs/setup/production-environment/container-runtimes/#containerd).

Se o pacote disponível tiver outra versão principal ou o campo não existir, consulte sua documentação antes de adaptar: não presuma que a configuração de 1.x funciona em qualquer versão. Capture versão e configuração relevante sem credenciais para a evidência do módulo.

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

Antes do init/join, kubelet reiniciando e runtime indicando `NetworkReady=false` por falta de CNI são esperados. CRI inacessível não é esperado. Para diagnosticá-lo, use `sudo journalctl -u containerd -n 80 --no-pager`. Registre a versão Debian exata e a versão de Kubernetes resultante; não substitua 1.35 por `latest` ao repetir. [Instalação oficial dos pacotes](https://kubernetes.io/docs/setup/production-environment/tools/kubeadm/install-kubeadm/).

## 4. Inicializar apenas cp1

**HOST CP.** Os prompts evitam usar um IP de exemplo por acidente. Escolha o endereço privado real da interface usada pelos nós. Os CIDRs informados serão reutilizados no Calico.

```bash
read -r -p 'IP privado real de cp1: ' CP_IP
read -r -p 'CIDR exclusivo para Pods: ' POD_CIDR
read -r -p 'CIDR exclusivo para Services: ' SERVICE_CIDR
test -n "$CP_IP" && test -n "$POD_CIDR" && test -n "$SERVICE_CIDR" || { printf 'Preencha os três valores antes de inicializar.\n'; exit 1; }
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

**LOCAL — copiar o kubeconfig somente por SSH autorizado.** Você precisa de kubectl 1.35 instalado localmente e rota até a API privada. O comando abaixo usa o usuário padrão da AMI Ubuntu; adapte se você escolheu outro usuário.

```bash
install -d -m 700 "$HOME/.kube"
scp ubuntu@lab-k8s.internal:.kube/config "$HOME/.kube/curso-kubeconfig"
chmod 600 "$HOME/.kube/curso-kubeconfig"
export KUBECONFIG="$HOME/.kube/curso-kubeconfig"
kubectl config rename-context kubernetes-admin@kubernetes curso-kubeadm
kubectl config current-context
kubectl cluster-info
```

Exporte `KUBECONFIG` em cada terminal LOCAL usado no curso. Se seu computador ainda não tiver kubectl, siga a [instalação oficial para Linux](https://kubernetes.io/docs/tasks/tools/install-kubectl-linux/) selecionando a versão registrada e a arquitetura do **computador**, que pode ser amd64 mesmo com servidores arm64.

## 5. Instalar CNI e adicionar workers

**LOCAL.** Calico 3.32 suporta Kubernetes 1.35 e ARM64. Usaremos o operador e CRDs `crd.projectcalico.org/v1`, sem a migração opcional para CRDs v3 nativas que exigiria feature gate adicional no Kubernetes 1.35. O operador também tem seus recursos `operator.tigera.io/v1`. [Compatibilidade](https://docs.tigera.io/calico/latest/getting-started/kubernetes/requirements) e [instalação oficial](https://docs.tigera.io/calico/latest/getting-started/kubernetes/self-managed-onprem/onpremises).

```bash
curl -fL -o /tmp/calico-v1-crds-3.32.2.yaml https://raw.githubusercontent.com/projectcalico/calico/v3.32.2/manifests/v1_crd_projectcalico_org.yaml
curl -fL -o /tmp/tigera-operator-3.32.2.yaml https://raw.githubusercontent.com/projectcalico/calico/v3.32.2/manifests/tigera-operator.yaml
less /tmp/tigera-operator-3.32.2.yaml
kubectl create -f /tmp/calico-v1-crds-3.32.2.yaml
kubectl create -f /tmp/tigera-operator-3.32.2.yaml
kubectl wait --for=condition=Established crd/installations.operator.tigera.io --timeout=120s
```

Crie **LOCAL** um arquivo de configuração do seu laboratório, `calico-installation.yaml`, com seu editor. No campo `cidr`, substitua o exemplo pelo **mesmo POD_CIDR do init**. O conteúdo abaixo escolhe encapsulamento inclusive dentro da subnet; isso simplifica o primeiro laboratório AWS sem depender de rotas para cada Pod IP.

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
        cidr: 192.168.0.0/16 # TROQUE se seu POD_CIDR for diferente
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

## Evidência, falha e recuperação

**Sucesso:** três Nodes `Ready`, versão igual à registrada, CoreDNS disponível, Calico sem degradação e API `/readyz` aprovada. Rode o laboratório 02 para comprovar DNS e HTTP entre pods; `Ready` dos nós, sozinho, não prova todas as rotas. Explique por que `/var/lib/etcd` contém estado do cluster e não os uploads da aplicação.

**Falha guiada — HOST WORKER worker2, 10 minutos:** confirme que é o worker de laboratório e execute `sudo systemctl stop kubelet`. **LOCAL:** observe `kubectl get nodes -w` e `kubectl describe node worker2`. Registre quanto demora até a condição mudar; isso depende de heartbeats e tolerâncias, não é instantâneo. Containers existentes podem continuar rodando porque kubelet e runtime são processos diferentes.

**Recuperação — HOST WORKER worker2:** `sudo systemctl start kubelet`; examine `sudo journalctl -u kubelet -n 80 --no-pager`. **LOCAL:** aguarde `kubectl wait --for=condition=Ready node/worker2 --timeout=180s` e confirme a API saudável. Não use reset para recuperar um serviço parado.

**Exercício autônomo, 60–90 minutos:** prepare um worker novo sem copiar a sequência inteira, usando somente sua lista de decisões e documentação oficial. Faça-o entrar no cluster e prove arquitetura, versão e Ready. Pode substituir worker2 somente depois de aprender drain no módulo 05; nesta etapa, use uma máquina adicional temporária ou apenas documente o procedimento sem remover nós em uso.

**Rubrica, 10 pontos:** 2 para explicar componentes e static Pods; 2 para versão/runtime/cgroups corretos; 2 para endpoint e firewall documentados; 2 para recuperação do kubelet; 2 para evidências e repetição independente. Avance com 8/10 e recuperação demonstrada. O script bootstrap legado do repositório pode ser lido depois para comparar escolhas e propor automação; ele não substitui esta primeira execução manual.

Fontes consultadas em **10/09/2026**, links junto aos mecanismos relevantes. Próximo: [02 — Workloads e reconciliação](02-workloads.md).
