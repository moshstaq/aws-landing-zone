variable "region" {
  description = "AWS region"
  type        = string
  default     = "us-east-1"
}

variable "github_org" {
  description = "GitHub organisation or username"
  type        = string
  default     = "moshstaq"
}

variable "github_repo" {
  description = "GitHub repository name for aws-landing-zone"
  type        = string
  default     = "aws-landing-zone"
}
