output "cluster_name" {
  value = aws_eks_cluster.lab.name
}

output "region" {
  value = var.region
}

output "vpc_id" {
  value = aws_vpc.lab.id
}

output "node_group" {
  value = aws_eks_node_group.lab.node_group_name
}

output "private_subnets" {
  value = aws_subnet.private[*].id
}
