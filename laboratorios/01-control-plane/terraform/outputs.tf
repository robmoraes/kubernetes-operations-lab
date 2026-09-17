output "region" {
  value = var.region
}

output "availability_zone" {
  value = local.availability_zone
}

output "ubuntu_ami_id" {
  description = "Registre este ID para repetir a mesma imagem na reconstrução manual."
  value       = nonsensitive(local.ubuntu_ami_id)
}

output "bootstrap_control_plane" {
  value = var.bootstrap_control_plane
}

output "node_instance_ids" {
  value = { for name, instance in aws_instance.node : name => instance.id }
}

output "node_private_ips" {
  value = { for name, instance in aws_instance.node : name => instance.private_ip }
}

output "node_public_ips" {
  description = "IPs temporários para saída; o SG não permite SSH direto da Internet."
  value       = { for name, instance in aws_instance.node : name => instance.public_ip }
}

output "ssh_commands" {
  description = "Comandos administrativos pelo EC2 Instance Connect Endpoint."
  value = {
    for name, instance in aws_instance.node : name =>
    "aws ec2-instance-connect ssh --region ${var.region} --instance-id ${instance.id} --os-user ubuntu --connection-type eice"
  }
}

output "cp1_instance_id" {
  value = aws_instance.node["cp1"].id
}

output "control_plane_endpoint" {
  value = "${local.control_plane_endpoint}:6443"
}

output "manual_handoff" {
  value = var.bootstrap_control_plane ? trimspace(<<-EOT
    1. Aguarde o marcador CURSO_CONTROL_PLANE_READY no console da instância.
    2. Entre em cp1 usando o comando de ssh_commands.
    3. Confira: sudo cloud-init status --wait && sudo test -f /var/lib/curso-bootstrap/control-plane-ready
    4. Gere o ingresso: sudo kubeadm token create --ttl 30m --print-join-command
    5. Em cada worker, aguarde cloud-init, confira o marcador host-prepared e só então execute o join com sudo.
  EOT
  ) : "Modo manual: as três instâncias contêm apenas a imagem Ubuntu original."
}
