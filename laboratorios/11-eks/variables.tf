variable "region" {
  type    = string
  default = "us-east-1"
}

variable "cluster_name" {
  type    = string
  default = "curso-eks"
}

variable "kubernetes_version" {
  type    = string
  default = "1.35"
}

variable "availability_zones" {
  type        = list(string)
  description = "Três AZs disponíveis na região, sem repetições."
  validation {
    condition     = length(var.availability_zones) == 3 && length(distinct(var.availability_zones)) == 3
    error_message = "Informe três AZs distintas."
  }
}

variable "admin_principal_arn" {
  type        = string
  description = "ARN IAM da role administrativa de estudo; não use ARN de sessão STS assumed-role."
  validation {
    condition     = can(regex("^arn:[^:]+:iam::[0-9]{12}:role/.+$", var.admin_principal_arn))
    error_message = "Use um ARN de IAM role existente."
  }
}

variable "admin_public_cidr" {
  type        = string
  description = "IPv4 público atual do administrador com /32. Endpoint privado também fica habilitado."
  validation {
    condition     = can(cidrhost(var.admin_public_cidr, 0)) && can(regex("/32$", var.admin_public_cidr))
    error_message = "Informe somente o IPv4 administrativo com /32."
  }
}

variable "addon_versions" {
  type        = map(string)
  description = "Versões exatas do describe-addon-versions compatíveis com Kubernetes e AMD64."
  validation {
    condition = alltrue([
      for name in ["vpc-cni", "coredns", "kube-proxy", "eks-pod-identity-agent", "aws-ebs-csi-driver"] :
      can(regex("^v[0-9]+\\.[0-9]+\\.[0-9]+-eksbuild\\.[0-9]+$", var.addon_versions[name]))
    ])
    error_message = "Informe versões EKS exatas dos cinco add-ons (vX.Y.Z-eksbuild.N)."
  }
}

variable "instance_type" {
  type    = string
  default = "c7i-flex.large"
}
