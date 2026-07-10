output "sns_topic_arn" {
  description = "ARN of the platform alerts SNS topic"
  value       = aws_sns_topic.platform_alerts.arn
}

output "cloudtrail_bucket" {
  description = "Name of the CloudTrail S3 bucket"
  value       = aws_s3_bucket.cloudtrail.bucket
}

output "cloudtrail_arn" {
  description = "ARN of the CloudTrail trail"
  value       = aws_cloudtrail.platform.arn
}

output "log_group_application" {
  description = "Name of the application log group"
  value       = aws_cloudwatch_log_group.application.name
}

output "log_group_platform" {
  description = "Name of the platform log group"
  value       = aws_cloudwatch_log_group.platform.name
}
