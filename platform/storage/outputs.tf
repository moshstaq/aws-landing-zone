output "bucket_name" {
  description = "Name of the application S3 bucket"
  value       = aws_s3_bucket.application.bucket
}

output "bucket_arn" {
  description = "ARN of the application S3 bucket"
  value       = aws_s3_bucket.application.arn
}


