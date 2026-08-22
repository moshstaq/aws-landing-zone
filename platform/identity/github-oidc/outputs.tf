output "stratum_platform_github_role_arn" {
  description = "ARN of the stratum-platform GitHub Actions role"
  value       = aws_iam_role.stratum_platform_github.arn
}

output "stratum_platform_terraform_role_arn" {
  description = "ARN of the stratum-platform Terraform provisioning role"
  value       = aws_iam_role.stratum_platform_terraform.arn
}

output "node_group_role_arn" {
  description = "ARN of the EKS node group role"
  value       = aws_iam_role.eks_node.arn
}
