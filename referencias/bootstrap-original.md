> Histórico preservado do README anterior. Não use esta página como roteiro inicial. Comece pelo [curso manual](../curso/01-control-plane.md); o script precisa de revisão/teste em VM descartável antes de uso. Nos blocos abaixo, os comandos eram executados na raiz do repositório.

# Kubernetes Cluster

- 3 control planes
- 2 workers
- rancher / portainer
- nginx / traefik
- volume persistente
- database (rds, local)
- prometheus
- loki
- grafana

## Bootstrap ARM64

O script [`bootstrap-kubernetes-arm64.sh`](../bootstrap-kubernetes-arm64.sh) prepara
hosts Debian/Ubuntu ARM64 para um cluster criado com `kubeadm`. Ele instala e
configura containerd, kubelet, kubeadm e kubectl, desabilita swap e aplica os
parametros de kernel necessarios.

### Primeiro control plane

Para um control plane simples:

```bash
chmod +x bootstrap-kubernetes-arm64.sh
sudo ./bootstrap-kubernetes-arm64.sh init
```

Para o cluster HA descrito acima, aponte um DNS ou load balancer para os control
planes e inicialize o primeiro no da seguinte forma:

```bash
sudo env \
  CONTROL_PLANE_ENDPOINT="k8s.exemplo.local:6443" \
  API_ADVERTISE_ADDRESS="192.168.1.10" \
  UPLOAD_CERTS=true \
  ./bootstrap-kubernetes-arm64.sh init
```

O Kubernetes precisa de um plugin CNI para que os nos fiquem `Ready`. E possivel
aplicar um manifesto automaticamente durante o `init`:

```bash
sudo env \
  CNI_MANIFEST_URL="https://endereco-do-manifesto/cni.yaml" \
  ./bootstrap-kubernetes-arm64.sh init
```

O CIDR padrao de pods e `10.244.0.0/16`; ajuste `POD_NETWORK_CIDR` conforme o CNI
escolhido.

### Workers e demais control planes

Ao final do `init`, o script imprime o comando de ingresso dos workers. Passe
somente os argumentos posteriores a `kubeadm join`:

```bash
sudo ./bootstrap-kubernetes-arm64.sh join \
  192.168.1.10:6443 \
  --token abcdef.0123456789abcdef \
  --discovery-token-ca-cert-hash sha256:<hash>
```

Para ingressar outro control plane, acrescente ao mesmo comando os argumentos
`--control-plane` e `--certificate-key` emitidos pelo primeiro `kubeadm init`.

Para apenas preparar um host, sem criar ou ingressar no cluster:

```bash
sudo ./bootstrap-kubernetes-arm64.sh prepare
```

Use `./bootstrap-kubernetes-arm64.sh --help` para consultar todas as variaveis.

> O script nao configura firewall, load balancer, DNS, armazenamento ou o CNI.
> Ele exige Debian/Ubuntu ARM64 com systemd e acesso aos repositorios APT.
