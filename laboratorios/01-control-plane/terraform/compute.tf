resource "aws_instance" "node" {
  for_each = local.nodes

  ami                                  = local.ubuntu_ami_id
  instance_type                        = var.instance_type
  subnet_id                            = aws_subnet.lab.id
  private_ip                           = each.value.private_ip
  associate_public_ip_address          = true
  vpc_security_group_ids               = [aws_security_group.nodes.id]
  instance_initiated_shutdown_behavior = "stop"
  ebs_optimized                        = true

  user_data = var.bootstrap_control_plane ? templatefile("${path.module}/templates/bootstrap.sh.tftpl", {
    node_name              = each.key
    node_role              = each.value.role
    cp_private_ip          = local.control_plane_private_ip
    worker1_private_ip     = local.nodes.worker1.private_ip
    worker2_private_ip     = local.nodes.worker2.private_ip
    control_plane_endpoint = local.control_plane_endpoint
    kubernetes_version     = var.kubernetes_version
    kubernetes_minor       = local.kubernetes_minor
    kubernetes_package     = local.kubernetes_package
    pod_cidr               = var.pod_cidr
    service_cidr           = var.service_cidr
    calico_version         = var.calico_version
  }) : null

  user_data_replace_on_change = true

  root_block_device {
    volume_type           = "gp3"
    volume_size           = var.root_volume_size
    iops                  = 3000
    throughput            = 125
    encrypted             = true
    delete_on_termination = true

    tags = {
      Name = "${local.name_prefix}-${each.key}-root"
      Node = each.key
    }
  }

  metadata_options {
    http_endpoint               = "enabled"
    http_tokens                 = "required"
    http_put_response_hop_limit = 1
    instance_metadata_tags      = "disabled"
  }

  dynamic "credit_specification" {
    for_each = startswith(var.instance_type, "t4g.") ? [1] : []
    content {
      cpu_credits = "standard"
    }
  }

  tags = {
    Name          = "${local.name_prefix}-${each.key}"
    Node          = each.key
    Role          = each.value.role
    BootstrapMode = var.bootstrap_control_plane ? "control-plane-handoff" : "manual"
  }

  lifecycle {
    precondition {
      condition     = data.aws_ami.selected.architecture == "x86_64" && data.aws_ami.selected.root_device_type == "ebs"
      error_message = "A AMI selecionada precisa ser AMD64 (x86_64) e usar root EBS."
    }
  }

  depends_on = [
    aws_route.internet,
    aws_route_table_association.lab,
  ]
}
