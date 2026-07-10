variable "region" {
  description = "AWS region"
  type        = string
  default     = "us-east-1"
}

variable "environment" {
  description = "Environment name"
  type        = string
  default     = "platform"
}

variable "alert_email" {
  description = "Email address for platform alert notifications"
  type        = string
  default     = "moshood@moshstaq.com"
}

variable "log_retention_days" {
  description = "CloudWatch log group retention in days"
  type        = number
  default     = 30
}
