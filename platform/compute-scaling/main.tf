# ── Data Sources ──────────────────────────────────────────────────────────────

data "aws_vpc" "platform" {
  tags = {
    Name = "vpc-platform"
  }
}

data "aws_subnets" "public" {
  filter {
    name   = "vpc-id"
    values = [data.aws_vpc.platform.id]
  }
  tags = {
    Tier = "public"
  }
}

data "aws_subnets" "private" {
  filter {
    name   = "vpc-id"
    values = [data.aws_vpc.platform.id]
  }
  tags = {
    Tier = "private"
  }
}

data "aws_ami" "amazon_linux_2" {
  most_recent = true
  owners      = ["amazon"]

  filter {
    name   = "name"
    values = ["amzn2-ami-hvm-*-x86_64-gp2"]
  }

  filter {
    name   = "state"
    values = ["available"]
  }
}

data "aws_iam_instance_profile" "ec2_ssm" {
  name = "profile-ec2-ssm-platform"
}

# ── Security Group — ALB ──────────────────────────────────────────────────────
# Internet-facing. Accepts HTTP and HTTPS from anywhere.
# No direct access to EC2 instances — traffic flows ALB → instances only.

resource "aws_security_group" "alb" {
  name        = "alb-sg-platform"
  description = "Security group for platform ALB"
  vpc_id      = data.aws_vpc.platform.id

  ingress {
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
    description = "HTTP from internet"
  }

  ingress {
    from_port   = 443
    to_port     = 443
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
    description = "HTTPS from internet"
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
    description = "All outbound"
  }

  tags = {
    Name = "alb-sg-platform"
  }
}

# ── Security Group — ASG Instances ───────────────────────────────────────────
# Private subnet instances. Only accepts traffic from the ALB security group.
# No direct internet access — ingress from ALB only.

resource "aws_security_group" "asg" {
  name        = "asg-sg-platform"
  description = "Security group for ASG instances"
  vpc_id      = data.aws_vpc.platform.id

  ingress {
    from_port       = 80
    to_port         = 80
    protocol        = "tcp"
    security_groups = [aws_security_group.alb.id]
    description     = "HTTP from ALB only"
  }

  egress {
    from_port   = 443
    to_port     = 443
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
    description = "HTTPS outbound for SSM Agent"
  }

  tags = {
    Name = "asg-sg-platform"
  }
}

# ── Application Load Balancer ─────────────────────────────────────────────────
# Internet-facing, deployed across public subnets in both AZs.
# Single point of entry for all inbound traffic.

resource "aws_lb" "platform" {
  name               = "alb-platform"
  internal           = false
  load_balancer_type = "application"
  security_groups    = [aws_security_group.alb.id]
  subnets            = data.aws_subnets.public.ids

  enable_deletion_protection = false

  tags = {
    Name = "alb-platform"
  }
}

# ── Target Group ──────────────────────────────────────────────────────────────
# ALB routes traffic to instances registered in this target group.
# ASG registers new instances here automatically on launch.
# Health check determines which instances receive traffic.

resource "aws_lb_target_group" "platform" {
  name     = "tg-platform"
  port     = 80
  protocol = "HTTP"
  vpc_id   = data.aws_vpc.platform.id

  health_check {
    enabled             = true
    healthy_threshold   = 2
    unhealthy_threshold = 3
    timeout             = 5
    interval            = 30
    path                = var.health_check_path
    matcher             = "200"
  }

  tags = {
    Name = "tg-platform"
  }
}

# ── ALB Listener ──────────────────────────────────────────────────────────────
# Listens on port 80 and forwards to the target group.
# HTTPS listener deferred — ACM certificate required.
# Production pattern: redirect HTTP → HTTPS, serve on 443 only.

resource "aws_lb_listener" "http" {
  load_balancer_arn = aws_lb.platform.arn
  port              = 80
  protocol          = "HTTP"

  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.platform.arn
  }
}

# ── Launch Template ───────────────────────────────────────────────────────────
# Blueprint for ASG instances. Defines everything the ASG needs to launch
# a new instance identically every time — AMI, type, profile, SG, metadata.
# Equivalent of a VM image profile in Azure VMSS.

resource "aws_launch_template" "platform" {
  name_prefix   = "lt-platform-"
  image_id      = data.aws_ami.amazon_linux_2.id
  instance_type = var.instance_type

  iam_instance_profile {
    name = data.aws_iam_instance_profile.ec2_ssm.name
  }

  vpc_security_group_ids = [aws_security_group.asg.id]

  metadata_options {
    http_endpoint               = "enabled"
    http_tokens                 = "required"
    http_put_response_hop_limit = 1
  }

  block_device_mappings {
    device_name = "/dev/xvda"
    ebs {
      volume_size           = 8
      volume_type           = "gp3"
      encrypted             = true
      delete_on_termination = true
    }
  }

  tag_specifications {
    resource_type = "instance"
    tags = {
      Name = "ec2-asg-platform"
    }
  }

  lifecycle {
    create_before_destroy = true
  }
}

# ── Auto Scaling Group ────────────────────────────────────────────────────────
# Maintains desired instance count, scales on demand.
# Deploys instances across private subnets in both AZs for HA.
# Registers instances with ALB target group automatically.

resource "aws_autoscaling_group" "platform" {
  name                = "asg-platform"
  vpc_zone_identifier = data.aws_subnets.private.ids
  target_group_arns   = [aws_lb_target_group.platform.arn]
  health_check_type   = "ELB"

  min_size         = var.asg_min_size
  max_size         = var.asg_max_size
  desired_capacity = var.asg_desired_capacity

  launch_template {
    id      = aws_launch_template.platform.id
    version = "$Latest"
  }

  tag {
    key                 = "Name"
    value               = "ec2-asg-platform"
    propagate_at_launch = true
  }

  lifecycle {
    create_before_destroy = true
  }
}

# ── Auto Scaling Policy ───────────────────────────────────────────────────────
# Target tracking policy — maintains average CPU at 70%.
# AWS automatically adds instances when CPU exceeds threshold
# and removes them when load drops. No manual threshold management.
# This is what absorbs flash sale traffic spikes automatically.

resource "aws_autoscaling_policy" "cpu_tracking" {
  name                   = "cpu-target-tracking-platform"
  autoscaling_group_name = aws_autoscaling_group.platform.name
  policy_type            = "TargetTrackingScaling"

  target_tracking_configuration {
    predefined_metric_specification {
      predefined_metric_type = "ASGAverageCPUUtilization"
    }
    target_value = 70.0
  }
}
