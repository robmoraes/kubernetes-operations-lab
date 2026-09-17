data "aws_availability_zones" "available" {
  state = "available"
}

data "aws_ssm_parameter" "ubuntu" {
  count = var.ubuntu_ami_id == null ? 1 : 0
  name  = "/aws/service/canonical/ubuntu/server/24.04/stable/current/amd64/hvm/ebs-gp3/ami-id"
}

locals {
  availability_zone        = coalesce(var.availability_zone, sort(data.aws_availability_zones.available.names)[0])
  name_prefix              = "${var.cluster_name}-${var.lab_run}"
  ubuntu_ami_id            = coalesce(var.ubuntu_ami_id, try(data.aws_ssm_parameter.ubuntu[0].value, null))
  kubernetes_minor         = join(".", slice(split(".", var.kubernetes_version), 0, 2))
  kubernetes_package       = "${var.kubernetes_version}-1.1"
  control_plane_endpoint   = "lab-k8s.internal"
  control_plane_private_ip = cidrhost(var.subnet_cidr, 10)

  nodes = {
    cp1 = {
      role       = "control-plane"
      private_ip = local.control_plane_private_ip
    }
    worker1 = {
      role       = "worker"
      private_ip = cidrhost(var.subnet_cidr, 11)
    }
    worker2 = {
      role       = "worker"
      private_ip = cidrhost(var.subnet_cidr, 12)
    }
  }
}

data "aws_ami" "selected" {
  filter {
    name   = "image-id"
    values = [local.ubuntu_ami_id]
  }
}
