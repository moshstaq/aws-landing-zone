output "cluster_name" {
  description = "Name of the EKS cluster"
  value       = aws_eks_cluster.platform.name
}

output "cluster_endpoint" {
  description = "Endpoint for the EKS control plane"
  value       = aws_eks_cluster.platform.endpoint
}

output "cluster_oidc_issuer" {
  description = "OIDC issuer URL for IRSA"
  value       = aws_eks_cluster.platform.identity[0].oidc[0].issuer
}

output "oidc_provider_arn" {
  description = "ARN of the EKS OIDC provider"
  value       = aws_iam_openid_connect_provider.eks.arn
}

output "app_pod_role_arn" {
  description = "ARN of the IRSA role for application pods"
  value       = aws_iam_role.app_pod.arn
}

