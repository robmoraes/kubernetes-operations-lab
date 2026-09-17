variable "region" {
  description = "Região AWS do laboratório."
  type        = string
  default     = "us-east-1"
}

variable "availability_zone" {
  description = "AZ única do primeiro cluster. Null escolhe a primeira AZ disponível da região."
  type        = string
  default     = null
  nullable    = true
}

variable "cluster_name" {
  description = "Nome lógico estável do cluster e prefixo kubelab dos recursos."
  type        = string
  default     = "kubelab"

  validation {
    condition     = var.cluster_name == "kubelab" || can(regex("^kubelab-[a-z0-9][a-z0-9-]{1,22}$", var.cluster_name))
    error_message = "Use kubelab ou um nome de até 31 caracteres com o prefixo kubelab-."
  }
}

variable "module_id" {
  description = "Contexto informativo da sessão para relatórios; não participa da identidade nem da seleção de recursos."
  type        = string

  validation {
    condition     = can(regex("^m(0[1-9]|1[0-2])$", var.module_id))
    error_message = "Use um identificador entre m01 e m12."
  }
}

variable "owner" {
  description = "Identificador público de quem revisará e destruirá o laboratório."
  type        = string
  default     = "dslab"

  validation {
    condition     = can(regex("^[A-Za-z0-9._-]+$", var.owner))
    error_message = "Use somente letras, números, ponto, sublinhado ou hífen."
  }
}

variable "cost_center" {
  description = "Dimensão estável para agrupar custos de estudo."
  type        = string
  default     = "estudo-kubernetes"

  validation {
    condition     = can(regex("^[A-Za-z0-9._-]+$", var.cost_center))
    error_message = "Use somente letras, números, ponto, sublinhado ou hífen."
  }
}

variable "lab_run" {
  description = "Identificador imutável desta execução, no formato run-AAAAMMDDThhmmssZ."
  type        = string

  validation {
    condition     = can(regex("^run-[0-9]{8}T[0-9]{6}Z$", var.lab_run))
    error_message = "Use o formato run-AAAAMMDDThhmmssZ, por exemplo run-20260915T120000Z."
  }
}

variable "expires_on" {
  description = "Data UTC esperada para remoção. É metadado e não agenda destruição."
  type        = string

  validation {
    condition     = can(regex("^[0-9]{4}-[0-9]{2}-[0-9]{2}$", var.expires_on))
    error_message = "Use uma data no formato AAAA-MM-DD."
  }
}

variable "vpc_cidr" {
  description = "CIDR da VPC descartável. Não pode sobrepor redes que serão conectadas ao laboratório."
  type        = string
  default     = "10.42.0.0/16"

  validation {
    condition     = can(cidrhost(var.vpc_cidr, 0))
    error_message = "Informe um CIDR IPv4 válido."
  }
}

variable "subnet_cidr" {
  description = "Subnet pública única; os nós continuam se comunicando por IP privado."
  type        = string
  default     = "10.42.10.0/24"

  validation {
    condition     = can(cidrhost(var.subnet_cidr, 12))
    error_message = "Informe um CIDR IPv4 com espaço para pelo menos 13 endereços."
  }
}

variable "pod_cidr" {
  description = "CIDR dos Pods, usado pelo kubeadm e pelo Calico."
  type        = string
  default     = "172.20.0.0/16"

  validation {
    condition     = can(cidrhost(var.pod_cidr, 0))
    error_message = "Informe um CIDR IPv4 válido."
  }
}

variable "service_cidr" {
  description = "CIDR virtual dos Services."
  type        = string
  default     = "10.96.0.0/12"

  validation {
    condition     = can(cidrhost(var.service_cidr, 0))
    error_message = "Informe um CIDR IPv4 válido."
  }
}

variable "instance_type" {
  description = "Tipo AMD64 com 2 vCPU e 4 GiB adotado pelo módulo 01."
  type        = string
  default     = "c7i-flex.large"
}

variable "root_volume_size" {
  description = "Tamanho em GiB do EBS raiz gp3 de cada nó."
  type        = number
  default     = 30

  validation {
    condition     = var.root_volume_size >= 30
    error_message = "O laboratório exige pelo menos 30 GiB por nó."
  }
}

variable "ubuntu_ami_id" {
  description = "AMI Ubuntu 24.04 AMD64 fixada. Null consulta a imagem corrente da Canonical no SSM."
  type        = string
  default     = null
  nullable    = true

  validation {
    condition     = var.ubuntu_ami_id == null || can(regex("^ami-[0-9a-f]+$", var.ubuntu_ami_id))
    error_message = "Informe um AMI ID válido ou null."
  }
}

variable "kubernetes_version" {
  description = "Patch Kubernetes fixado sem o prefixo v nem o sufixo Debian."
  type        = string
  default     = "1.35.8"

  validation {
    condition     = can(regex("^1\\.35\\.[0-9]+$", var.kubernetes_version))
    error_message = "Este laboratório aceita somente um patch da linha 1.35."
  }
}

variable "calico_version" {
  description = "Versão fixada do operador e CRDs do Calico."
  type        = string
  default     = "3.32.2"

  validation {
    condition     = can(regex("^[0-9]+\\.[0-9]+\\.[0-9]+$", var.calico_version))
    error_message = "Informe a versão Calico no formato X.Y.Z."
  }
}

variable "bootstrap_control_plane" {
  description = "True prepara todos os hosts e inicializa somente cp1; false entrega Ubuntu limpo para instalação manual."
  type        = bool
  default     = true
}
