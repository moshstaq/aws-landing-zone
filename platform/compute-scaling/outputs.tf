output "alb_dns_name" {
  description = "DNS name of the Application Load Balancer"
  value       = aws_lb.platform.dns_name
}

output "alb_arn" {
  description = "ARN of the Application Load Balancer"
  value       = aws_lb.platform.arn
}

output "target_group_arn" {
  description = "ARN of the ALB target group"
  value       = aws_lb_target_group.platform.arn
}

output "asg_name" {
  description = "Name of the Auto Scaling Group"
  value       = aws_autoscaling_group.platform.name
}

output "launch_template_id" {
  description = "ID of the Launch Template"
  value       = aws_launch_template.platform.id
}
