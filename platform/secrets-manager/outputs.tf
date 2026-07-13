output "database_secret_arn" {
  description = "ARN of the database secret"
  value       = aws_secretsmanager_secret.database.arn
}

output "app_config_secret_arn" {
  description = "ARN of the app config secret"
  value       = aws_secretsmanager_secret.app_config.arn
}
