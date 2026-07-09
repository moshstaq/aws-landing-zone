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

variable "log_retention_days" {
  description = "Days before expiring diagnostic logs"
  type        = number
  default     = 90
}

variable "transition_to_ia_days" {
  description = "Days before transitioning objects to Standard-IA"
  type        = number
  default     = 30
}
