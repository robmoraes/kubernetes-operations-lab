locals {
  aws_policy_prefix = "arn:${data.aws_partition.current.partition}:iam::aws:policy"
  node_policies = {
    worker = "AmazonEKSWorkerNodePolicy"
    ecr    = "AmazonEC2ContainerRegistryPullOnly"
    # Simplificação inicial: no desafio, migre CNI para uma role própria.
    cni = "AmazonEKS_CNI_Policy"
  }
}

resource "aws_iam_role" "cluster" {
  name = "${var.cluster_name}-cluster"
  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Allow"
      Action    = "sts:AssumeRole"
      Principal = { Service = "eks.amazonaws.com" }
    }]
  })
}

resource "aws_iam_role_policy_attachment" "cluster" {
  role       = aws_iam_role.cluster.name
  policy_arn = "${local.aws_policy_prefix}/AmazonEKSClusterPolicy"
}

resource "aws_cloudwatch_log_group" "cluster" {
  name              = "/aws/eks/${var.cluster_name}/cluster"
  retention_in_days = 7
}

resource "aws_eks_cluster" "lab" {
  name                      = var.cluster_name
  role_arn                  = aws_iam_role.cluster.arn
  version                   = var.kubernetes_version
  enabled_cluster_log_types = ["api", "audit", "authenticator"]
  access_config {
    authentication_mode                         = "API"
    bootstrap_cluster_creator_admin_permissions = false
  }
  vpc_config {
    subnet_ids              = aws_subnet.private[*].id
    endpoint_private_access = true
    endpoint_public_access  = true
    public_access_cidrs     = [var.admin_public_cidr]
  }
  kubernetes_network_config {
    service_ipv4_cidr = "172.20.0.0/16"
  }
  depends_on = [aws_iam_role_policy_attachment.cluster, aws_cloudwatch_log_group.cluster]
}

resource "aws_eks_access_entry" "admin" {
  cluster_name  = aws_eks_cluster.lab.name
  principal_arn = var.admin_principal_arn
  type          = "STANDARD"
}

resource "aws_eks_access_policy_association" "admin" {
  cluster_name  = aws_eks_cluster.lab.name
  principal_arn = aws_eks_access_entry.admin.principal_arn
  policy_arn    = "arn:${data.aws_partition.current.partition}:eks::aws:cluster-access-policy/AmazonEKSClusterAdminPolicy"
  access_scope {
    type = "cluster"
  }
}

resource "aws_iam_role" "node" {
  name = "${var.cluster_name}-nodes"
  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Allow"
      Action    = "sts:AssumeRole"
      Principal = { Service = "ec2.amazonaws.com" }
    }]
  })
}

resource "aws_iam_role_policy_attachment" "node" {
  for_each   = local.node_policies
  role       = aws_iam_role.node.name
  policy_arn = "${local.aws_policy_prefix}/${each.value}"
}

resource "aws_eks_node_group" "lab" {
  cluster_name    = aws_eks_cluster.lab.name
  node_group_name = "amd64-lab"
  node_role_arn   = aws_iam_role.node.arn
  subnet_ids      = aws_subnet.private[*].id
  version         = var.kubernetes_version
  ami_type        = "AL2023_x86_64_STANDARD"
  instance_types  = [var.instance_type]
  capacity_type   = "ON_DEMAND"
  disk_size       = 30
  scaling_config {
    desired_size = 3
    min_size     = 3
    max_size     = 4
  }
  update_config {
    max_unavailable = 1
  }
  depends_on = [aws_iam_role_policy_attachment.node, aws_route.nat, aws_route_table_association.private]
}

# Converte add-ons iniciais em gerenciados; OVERWRITE é intencional na primeira adoção.
resource "aws_eks_addon" "core" {
  for_each                    = toset(["vpc-cni", "coredns", "kube-proxy", "eks-pod-identity-agent"])
  cluster_name                = aws_eks_cluster.lab.name
  addon_name                  = each.value
  addon_version               = var.addon_versions[each.value]
  resolve_conflicts_on_create = "OVERWRITE"
  depends_on                  = [aws_eks_node_group.lab]
}

resource "aws_iam_role" "ebs" {
  name = "${var.cluster_name}-ebs-csi"
  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Allow"
      Action    = ["sts:AssumeRole", "sts:TagSession"]
      Principal = { Service = "pods.eks.amazonaws.com" }
    }]
  })
}

resource "aws_iam_role_policy_attachment" "ebs" {
  role       = aws_iam_role.ebs.name
  policy_arn = "${local.aws_policy_prefix}/service-role/AmazonEBSCSIDriverPolicyV2"
}

resource "aws_eks_pod_identity_association" "ebs" {
  cluster_name    = aws_eks_cluster.lab.name
  namespace       = "kube-system"
  service_account = "ebs-csi-controller-sa"
  role_arn        = aws_iam_role.ebs.arn
  depends_on      = [aws_eks_addon.core, aws_iam_role_policy_attachment.ebs]
}

resource "aws_eks_addon" "ebs" {
  cluster_name  = aws_eks_cluster.lab.name
  addon_name    = "aws-ebs-csi-driver"
  addon_version = var.addon_versions["aws-ebs-csi-driver"]
  depends_on    = [aws_eks_pod_identity_association.ebs]
}
