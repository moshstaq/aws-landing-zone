output "repository_url" {
  description = "URL of the ECR repository"
  value       = aws_ecr_repository.platform.repository_url
}

output "repository_arn" {
  description = "ARN of the ECR repository"
  value       = aws_ecr_repository.platform.arn
}

output "registry_id" {
  description = "Registry ID (AWS account ID)"
  value       = aws_ecr_repository.platform.registry_id
}
