resource "aws_vpc" "lab" {
  cidr_block           = var.vpc_cidr
  enable_dns_support   = true
  enable_dns_hostnames = true

  tags = {
    Name = "${local.name_prefix}-vpc"
  }
}

resource "aws_internet_gateway" "lab" {
  vpc_id = aws_vpc.lab.id

  tags = {
    Name = "${local.name_prefix}-igw"
  }
}

resource "aws_subnet" "lab" {
  vpc_id                  = aws_vpc.lab.id
  cidr_block              = var.subnet_cidr
  availability_zone       = local.availability_zone
  map_public_ip_on_launch = false

  tags = {
    Name = "${local.name_prefix}-subnet"
  }
}

resource "aws_route_table" "lab" {
  vpc_id = aws_vpc.lab.id

  tags = {
    Name = "${local.name_prefix}-routes"
  }
}

resource "aws_route" "internet" {
  route_table_id         = aws_route_table.lab.id
  destination_cidr_block = "0.0.0.0/0"
  gateway_id             = aws_internet_gateway.lab.id
}

resource "aws_route_table_association" "lab" {
  subnet_id      = aws_subnet.lab.id
  route_table_id = aws_route_table.lab.id
}

resource "aws_security_group" "nodes" {
  name_prefix = "${local.name_prefix}-nodes-"
  description = "Trafego privado entre os nos do cluster kubeadm"
  vpc_id      = aws_vpc.lab.id

  tags = {
    Name = "${local.name_prefix}-nodes"
  }

  lifecycle {
    create_before_destroy = true
  }
}

resource "aws_security_group" "eice" {
  name_prefix = "${local.name_prefix}-eice-"
  description = "Saida SSH do EC2 Instance Connect Endpoint"
  vpc_id      = aws_vpc.lab.id

  tags = {
    Name = "${local.name_prefix}-eice"
  }

  lifecycle {
    create_before_destroy = true
  }
}

resource "aws_vpc_security_group_ingress_rule" "ssh_from_eice" {
  security_group_id            = aws_security_group.nodes.id
  referenced_security_group_id = aws_security_group.eice.id
  ip_protocol                  = "tcp"
  from_port                    = 22
  to_port                      = 22
  description                  = "SSH somente pelo EC2 Instance Connect Endpoint"
}

resource "aws_vpc_security_group_ingress_rule" "api_between_nodes" {
  security_group_id            = aws_security_group.nodes.id
  referenced_security_group_id = aws_security_group.nodes.id
  ip_protocol                  = "tcp"
  from_port                    = 6443
  to_port                      = 6443
  description                  = "API Server acessada pelos membros do cluster"
}

resource "aws_vpc_security_group_ingress_rule" "kubelet_between_nodes" {
  security_group_id            = aws_security_group.nodes.id
  referenced_security_group_id = aws_security_group.nodes.id
  ip_protocol                  = "tcp"
  from_port                    = 10250
  to_port                      = 10250
  description                  = "API autenticada dos kubelets"
}

resource "aws_vpc_security_group_ingress_rule" "calico_vxlan" {
  security_group_id            = aws_security_group.nodes.id
  referenced_security_group_id = aws_security_group.nodes.id
  ip_protocol                  = "udp"
  from_port                    = 4789
  to_port                      = 4789
  description                  = "Overlay VXLAN do Calico"
}

resource "aws_vpc_security_group_ingress_rule" "calico_typha" {
  security_group_id            = aws_security_group.nodes.id
  referenced_security_group_id = aws_security_group.nodes.id
  ip_protocol                  = "tcp"
  from_port                    = 5473
  to_port                      = 5473
  description                  = "Calico Typha entre nos"
}

resource "aws_vpc_security_group_egress_rule" "nodes_outbound" {
  security_group_id = aws_security_group.nodes.id
  ip_protocol       = "-1"
  cidr_ipv4         = "0.0.0.0/0"
  description       = "DNS, horario, repositorios e registries"
}

resource "aws_vpc_security_group_egress_rule" "eice_to_ssh" {
  security_group_id            = aws_security_group.eice.id
  referenced_security_group_id = aws_security_group.nodes.id
  ip_protocol                  = "tcp"
  from_port                    = 22
  to_port                      = 22
  description                  = "Tunel administrativo para os nos"
}

resource "aws_ec2_instance_connect_endpoint" "lab" {
  subnet_id          = aws_subnet.lab.id
  security_group_ids = [aws_security_group.eice.id]
  preserve_client_ip = false

  tags = {
    Name = "${local.name_prefix}-eice"
  }
}
