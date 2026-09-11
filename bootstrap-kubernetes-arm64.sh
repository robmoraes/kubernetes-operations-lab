#!/usr/bin/env bash

set -Eeuo pipefail

readonly SCRIPT_NAME="${0##*/}"
readonly KUBELET_SERVICE="kubelet"
readonly CONTAINERD_SOCKET="unix:///run/containerd/containerd.sock"

KUBERNETES_MINOR="${KUBERNETES_MINOR:-v1.35}"
POD_NETWORK_CIDR="${POD_NETWORK_CIDR:-10.244.0.0/16}"
SERVICE_CIDR="${SERVICE_CIDR:-10.96.0.0/12}"
CONTROL_PLANE_ENDPOINT="${CONTROL_PLANE_ENDPOINT:-}"
API_ADVERTISE_ADDRESS="${API_ADVERTISE_ADDRESS:-}"
NODE_IP="${NODE_IP:-}"
CNI_MANIFEST_URL="${CNI_MANIFEST_URL:-}"
UPLOAD_CERTS="${UPLOAD_CERTS:-false}"

log() {
  printf '[%s] %s\n' "$(date '+%Y-%m-%d %H:%M:%S')" "$*"
}

die() {
  printf 'ERRO: %s\n' "$*" >&2
  exit 1
}

usage() {
  cat <<EOF
Uso:
  sudo ./${SCRIPT_NAME} prepare
  sudo ./${SCRIPT_NAME} init
  sudo ./${SCRIPT_NAME} join <host:porta> --token <token> \\
    --discovery-token-ca-cert-hash sha256:<hash>

Comandos:
  prepare  Prepara o host e instala containerd, kubelet, kubeadm e kubectl.
  init     Executa prepare e inicializa o primeiro control plane.
  join     Executa prepare e ingressa o host no cluster com kubeadm join.

Variaveis opcionais:
  KUBERNETES_MINOR          Repositorio minor do Kubernetes (padrao: v1.35)
  POD_NETWORK_CIDR          CIDR dos pods (padrao: 10.244.0.0/16)
  SERVICE_CIDR              CIDR dos Services (padrao: 10.96.0.0/12)
  CONTROL_PLANE_ENDPOINT    Endpoint estavel para HA, por exemplo k8s.exemplo:6443
  API_ADVERTISE_ADDRESS     IP anunciado por este control plane
  NODE_IP                   IP usado pelo kubelet em hosts com varias interfaces
  CNI_MANIFEST_URL          Manifesto CNI aplicado depois do init (vazio = nao aplica)
  UPLOAD_CERTS              true para kubeadm init --upload-certs

Somente Debian/Ubuntu ARM64 (aarch64) com systemd.
EOF
}

require_root() {
  [[ ${EUID} -eq 0 ]] || die "execute como root (por exemplo: sudo ./${SCRIPT_NAME} $*)"
}

validate_host() {
  [[ -r /etc/os-release ]] || die "/etc/os-release nao encontrado"

  # shellcheck disable=SC1091
  source /etc/os-release
  case "${ID:-}" in
    debian|ubuntu) ;;
    *) die "distribuicao nao suportada: ${ID:-desconhecida}; use Debian ou Ubuntu" ;;
  esac

  case "$(uname -m)" in
    aarch64|arm64) ;;
    armv7l|armhf)
      die "ARM 32 bits nao e suportado pelos pacotes Kubernetes atuais; instale um sistema ARM64"
      ;;
    *) die "arquitetura nao suportada: $(uname -m); este script requer ARM64" ;;
  esac

  command -v systemctl >/dev/null 2>&1 || die "systemd e obrigatorio"
  [[ ${KUBERNETES_MINOR} =~ ^v[0-9]+\.[0-9]+$ ]] || \
    die "KUBERNETES_MINOR invalido: ${KUBERNETES_MINOR} (formato esperado: v1.35)"
}

install_prerequisites() {
  log "Instalando dependencias basicas"
  export DEBIAN_FRONTEND=noninteractive
  apt-get update
  apt-get install -y apt-transport-https ca-certificates curl gpg containerd
}

disable_swap() {
  log "Desabilitando swap"
  swapoff -a

  if [[ -f /etc/fstab ]]; then
    cp --archive --no-clobber /etc/fstab /etc/fstab.k8s-bootstrap.bak
    sed -ri \
      '/^[[:space:]]*#/! s@^([^#]*[[:space:]]+swap[[:space:]]+.*)$@# disabled by kubernetes-bootstrap: \1@' \
      /etc/fstab
  fi
}

configure_kernel() {
  log "Configurando modulos e parametros de rede do kernel"
  cat >/etc/modules-load.d/k8s.conf <<'EOF'
overlay
br_netfilter
EOF

  modprobe overlay
  modprobe br_netfilter

  cat >/etc/sysctl.d/99-kubernetes-cri.conf <<'EOF'
net.bridge.bridge-nf-call-iptables  = 1
net.bridge.bridge-nf-call-ip6tables = 1
net.ipv4.ip_forward                 = 1
EOF
  sysctl --system >/dev/null
}

configure_containerd() {
  log "Configurando containerd com cgroups do systemd"
  mkdir -p /etc/containerd

  if [[ ! -s /etc/containerd/config.toml ]]; then
    containerd config default >/etc/containerd/config.toml
  fi

  # Algumas distribuicoes entregam o plugin CRI desabilitado por padrao.
  if grep -Eq '^[[:space:]]*disabled_plugins[[:space:]]*=.*"cri"' /etc/containerd/config.toml; then
    sed -ri '/^[[:space:]]*disabled_plugins[[:space:]]*=.*"cri"/d' /etc/containerd/config.toml
  fi

  if grep -Eq 'SystemdCgroup[[:space:]]*=' /etc/containerd/config.toml; then
    sed -ri 's/(SystemdCgroup[[:space:]]*=[[:space:]]*)false/\1true/' /etc/containerd/config.toml
  else
    die "nao foi possivel localizar SystemdCgroup em /etc/containerd/config.toml"
  fi

  systemctl enable --now containerd
  systemctl restart containerd
  systemctl is-active --quiet containerd || die "containerd nao iniciou corretamente"
}

configure_kubernetes_repository() {
  local keyring=/etc/apt/keyrings/kubernetes-apt-keyring.gpg
  local repository="https://pkgs.k8s.io/core:/stable:/${KUBERNETES_MINOR}/deb/"
  local temp_key

  log "Configurando repositorio Kubernetes ${KUBERNETES_MINOR}"
  mkdir -p /etc/apt/keyrings
  temp_key="$(mktemp)"
  trap 'rm -f "${temp_key:-}"' RETURN
  curl --fail --location --silent --show-error "${repository}Release.key" --output "${temp_key}"
  gpg --batch --yes --dearmor --output "${keyring}" "${temp_key}"
  chmod 0644 "${keyring}"

  printf 'deb [signed-by=%s] %s /\n' "${keyring}" "${repository}" \
    >/etc/apt/sources.list.d/kubernetes.list
}

install_kubernetes() {
  log "Instalando kubelet, kubeadm e kubectl"
  apt-get update
  apt-get install -y kubelet kubeadm kubectl
  apt-mark hold kubelet kubeadm kubectl

  if [[ -n ${NODE_IP} ]]; then
    printf 'KUBELET_EXTRA_ARGS=--node-ip=%s\n' "${NODE_IP}" >/etc/default/kubelet
  fi

  systemctl enable "${KUBELET_SERVICE}"
}

prepare_node() {
  validate_host
  install_prerequisites
  disable_swap
  configure_kernel
  configure_containerd
  configure_kubernetes_repository
  install_kubernetes
  log "Host preparado com sucesso"
}

install_user_kubeconfig() {
  local target_user target_home target_group kube_dir

  target_user="${SUDO_USER:-root}"
  target_home="$(getent passwd "${target_user}" | cut -d: -f6)"
  target_group="$(id -gn "${target_user}")"
  [[ -n ${target_home} ]] || die "nao foi possivel descobrir o HOME de ${target_user}"

  kube_dir="${target_home}/.kube"
  install -d -m 0700 -o "${target_user}" -g "${target_group}" "${kube_dir}"
  install -m 0600 -o "${target_user}" -g "${target_group}" \
    /etc/kubernetes/admin.conf "${kube_dir}/config"
}

init_control_plane() {
  local -a init_args

  [[ ! -f /etc/kubernetes/admin.conf ]] || \
    die "este host ja parece inicializado; /etc/kubernetes/admin.conf existe"

  prepare_node

  init_args=(
    init
    "--cri-socket=${CONTAINERD_SOCKET}"
    "--pod-network-cidr=${POD_NETWORK_CIDR}"
    "--service-cidr=${SERVICE_CIDR}"
  )

  [[ -z ${CONTROL_PLANE_ENDPOINT} ]] || \
    init_args+=("--control-plane-endpoint=${CONTROL_PLANE_ENDPOINT}")
  [[ -z ${API_ADVERTISE_ADDRESS} ]] || \
    init_args+=("--apiserver-advertise-address=${API_ADVERTISE_ADDRESS}")
  [[ ${UPLOAD_CERTS} != true ]] || init_args+=(--upload-certs)

  log "Inicializando control plane"
  kubeadm "${init_args[@]}"
  install_user_kubeconfig

  if [[ -n ${CNI_MANIFEST_URL} ]]; then
    log "Instalando CNI de ${CNI_MANIFEST_URL}"
    KUBECONFIG=/etc/kubernetes/admin.conf kubectl apply -f "${CNI_MANIFEST_URL}"
  else
    log "CNI nao instalado; defina CNI_MANIFEST_URL ou aplique seu plugin de rede manualmente"
  fi

  log "Comando para adicionar workers:"
  kubeadm token create --print-join-command
}

join_cluster() {
  local -a join_args=("$@")
  local argument
  local has_cri_socket=false

  ((${#join_args[@]} > 0)) || die "informe os argumentos gerados por 'kubeadm token create --print-join-command'"
  [[ ! -f /etc/kubernetes/kubelet.conf ]] || \
    die "este host ja parece fazer parte de um cluster"

  prepare_node

  for argument in "${join_args[@]}"; do
    [[ ${argument} != --cri-socket && ${argument} != --cri-socket=* ]] || has_cri_socket=true
  done
  [[ ${has_cri_socket} == true ]] || join_args+=("--cri-socket=${CONTAINERD_SOCKET}")

  log "Ingressando o host no cluster"
  kubeadm join "${join_args[@]}"
}

main() {
  local command="${1:-}"
  [[ -n ${command} ]] || {
    usage
    exit 2
  }
  shift || true

  case "${command}" in
    prepare)
      require_root "prepare"
      prepare_node
      ;;
    init)
      require_root "init"
      init_control_plane
      ;;
    join)
      require_root "join"
      join_cluster "$@"
      ;;
    -h|--help|help)
      usage
      ;;
    *)
      usage >&2
      die "comando desconhecido: ${command}"
      ;;
  esac
}

main "$@"
