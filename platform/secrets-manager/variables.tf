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

variable "recovery_window_days" {
  description = "Days before a deleted secret is permanently removed"
  type        = number
  default     = 7
}
