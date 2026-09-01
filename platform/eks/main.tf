# ── Data Sources ──────────────────────────────────────────────────────────────

data "aws_vpc" "platform" {
  tags = {
    Name = "vpc-platform"
  }
}

data "aws_subnets" "private" {
  filter {
    name   = "vpc-id"
    values = [data.aws_vpc.platform.id]
  }
  tags = {
    Tier = "private"
  }
}

data "aws_caller_identity" "current" {}

# ── EKS Cluster IAM Role ──────────────────────────────────────────────────────
# The cluster role allows EKS control plane to manage AWS resources
# on your behalf — creating load balancers, managing security groups,
# and communicating with worker nodes.

data "aws_iam_policy_document" "eks_cluster_trust" {
  statement {
    effect  = "Allow"
    actions = ["sts:AssumeRole"]

    principals {
      type        = "Service"
      identifiers = ["eks.amazonaws.com"]
    }
  }
}

resource "aws_iam_role" "eks_cluster" {
  name               = "role-eks-cluster-platform"
  assume_role_policy = data.aws_iam_policy_document.eks_cluster_trust.json
  description        = "EKS cluster role allows control plane to manage AWS resources"
}

resource "aws_iam_role_policy_attachment" "eks_cluster_policy" {
  role       = aws_iam_role.eks_cluster.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonEKSClusterPolicy"
}

# ── EKS Node Group IAM Role ───────────────────────────────────────────────────
# Worker node role — three managed policies covering cluster
# communication, VPC networking for pods, and ECR image pulls.

data "aws_iam_role" "eks_node" {
  name = "role-eks-node-platform"
}

# ── EKS Cluster ───────────────────────────────────────────────────────────────
# Control plane deployed across private subnets.
# Endpoint access: public for kubectl from local machine,
# private for node-to-control-plane communication within VPC.

resource "aws_eks_cluster" "platform" {
  name     = "eks-platform"
  role_arn = aws_iam_role.eks_cluster.arn
  version  = var.cluster_version

  vpc_config {
    subnet_ids              = data.aws_subnets.private.ids
    endpoint_private_access = true
    endpoint_public_access  = true
  }

  depends_on = [
    aws_iam_role_policy_attachment.eks_cluster_policy
  ]

  tags = {
    Name = "eks-platform"
  }
}

# ── OIDC Provider for IRSA ────────────────────────────────────────────────────
# EKS creates an OIDC provider for the cluster. IRSA uses this
# to allow pods to exchange Kubernetes service account tokens
# for AWS credentials — same OIDC pattern as GitHub Actions.
# The pattern repeats: define a trusted issuer, scope by subject claim.

data "tls_certificate" "eks" {
  url = aws_eks_cluster.platform.identity[0].oidc[0].issuer
}

resource "aws_iam_openid_connect_provider" "eks" {
  client_id_list  = ["sts.amazonaws.com"]
  thumbprint_list = [data.tls_certificate.eks.certificates[0].sha1_fingerprint]
  url             = aws_eks_cluster.platform.identity[0].oidc[0].issuer
}

# ── EKS Node Group ────────────────────────────────────────────────────────────
# Managed node group — AWS handles node provisioning, updates,
# and replacement. Nodes deploy across private subnets for security.
# t3.medium minimum for EKS — t3.micro is too small for system pods.

resource "aws_eks_node_group" "platform" {
  cluster_name    = aws_eks_cluster.platform.name
  node_group_name = "ng-platform"
  node_role_arn   = data.aws_iam_role.eks_node.arn
  subnet_ids      = data.aws_subnets.private.ids

  instance_types = [var.node_instance_type]

  scaling_config {
    desired_size = var.node_desired_size
    min_size     = var.node_min_size
    max_size     = var.node_max_size
  }

  update_config {
    max_unavailable = 1
  }

  depends_on = [
    aws_eks_cluster.platform
  ]

  tags = {
    Name = "eks-node-platform"
  }
}

# ── IRSA — Application Pod Role ───────────────────────────────────────────────
# Pod-level IAM role for the Stratum application.
# Trust policy scoped to the specific Kubernetes service account
# in the specific namespace — least privilege at the pod level.
# Same OIDC token exchange pattern as GitHub Actions role chaining.

locals {
  oidc_issuer = replace(
    aws_eks_cluster.platform.identity[0].oidc[0].issuer,
    "https://",
    ""
  )
}

data "aws_iam_policy_document" "app_pod_trust" {
  statement {
    effect  = "Allow"
    actions = ["sts:AssumeRoleWithWebIdentity"]

    principals {
      type        = "Federated"
      identifiers = [aws_iam_openid_connect_provider.eks.arn]
    }

    condition {
      test     = "StringEquals"
      variable = "${local.oidc_issuer}:aud"
      values   = ["sts.amazonaws.com"]
    }

    condition {
      test     = "StringLike"
      variable = "${local.oidc_issuer}:sub"
      values = [
        "system:serviceaccount:stratum:stratum-app",
        "system:serviceaccount:stratum-workloads:stratum-catalogue",
        "system:serviceaccount:stratum-workloads:stratum-orders"
      ]
    }
  }
}

resource "aws_iam_role" "app_pod" {
  name               = "role-eks-app-stratum"
  assume_role_policy = data.aws_iam_policy_document.app_pod_trust.json
  description        = "IRSA role for Stratum application pods"
}

data "aws_iam_policy_document" "app_pod_permissions" {
  statement {
    sid    = "SecretsManagerRead"
    effect = "Allow"
    actions = [
      "secretsmanager:GetSecretValue",
      "secretsmanager:DescribeSecret"
    ]
    resources = [
      "arn:aws:secretsmanager:us-east-1:${data.aws_caller_identity.current.account_id}:secret:stratum/platform/*"
    ]
  }
}

resource "aws_iam_role_policy" "app_pod" {
  name   = "stratum-app-permissions"
  role   = aws_iam_role.app_pod.id
  policy = data.aws_iam_policy_document.app_pod_permissions.json
}

# ── Container Insights ────────────────────────────────────────────────────────
# Enables CloudWatch Container Insights for pod-level observability.
# Pushes CPU, memory, network, restart count, and container status
# to CloudWatch automatically. No application code changes required.

resource "aws_eks_addon" "cloudwatch_observability" {
  cluster_name = aws_eks_cluster.platform.name
  addon_name   = "amazon-cloudwatch-observability"

  depends_on = [
    aws_eks_node_group.platform
  ]
}

