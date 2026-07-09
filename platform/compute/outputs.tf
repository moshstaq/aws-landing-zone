output "instance_id" {
  description = "ID of the platform EC2 instance"
  value       = aws_instance.platform.id
}

output "instance_private_ip" {
  description = "Private IP of the platform EC2 instance"
  value       = aws_instance.platform.private_ip
}

output "security_group_id" {
  description = "ID of the EC2 security group"
  value       = aws_security_group.ec2_ssm.id
}

output "iam_role_arn" {
  description = "ARN of the EC2 SSM IAM role"
  value       = aws_iam_role.ec2_ssm.arn
}
