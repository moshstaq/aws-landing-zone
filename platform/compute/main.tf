# ── Data Sources — Networking ─────────────────────────────────────────────────
# Consumes networking outputs via data sources.
# No remote state reference — data sources only per ADR-001.

data "aws_vpc" "platform" {
  tags = {
    Name = "vpc-platform"
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

# ── Latest Amazon Linux 2 AMI ─────────────────────────────────────────────────
# Dynamically resolves the latest Amazon Linux 2 AMI for the region.
# Avoids hardcoding AMI IDs which are region-specific and change over time.

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

# ── IAM Role for EC2 ──────────────────────────────────────────────────────────
# Allows EC2 instances to assume this role via the instance profile.
# SSM Agent uses the attached policy to register with Systems Manager.

data "aws_iam_policy_document" "ec2_trust" {
  statement {
    effect  = "Allow"
    actions = ["sts:AssumeRole"]

    principals {
      type        = "Service"
      identifiers = ["ec2.amazonaws.com"]
    }
  }
}

resource "aws_iam_role" "ec2_ssm" {
  name               = "role-ec2-ssm-platform"
  assume_role_policy = data.aws_iam_policy_document.ec2_trust.json
  description        = "Allows EC2 instances to use SSM Session Manager"
}

resource "aws_iam_role_policy_attachment" "ssm_core" {
  role       = aws_iam_role.ec2_ssm.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonSSMManagedInstanceCore"
}

# ── IAM Instance Profile ──────────────────────────────────────────────────────
# Wrapper that attaches the IAM role to EC2 instances.
# EC2 cannot use a role directly — it must be wrapped in an instance profile.

resource "aws_iam_instance_profile" "ec2_ssm" {
  name = "profile-ec2-ssm-platform"
  role = aws_iam_role.ec2_ssm.name
}

# ── Security Group ────────────────────────────────────────────────────────────
# No inbound rules — SSM Session Manager does not require port 22.
# Outbound HTTPS required for SSM Agent to communicate with Systems Manager.

resource "aws_security_group" "ec2_ssm" {
  name        = "ec2-ssm-sg-platform"
  description = "Security group for SSM-managed EC2 instances"
  vpc_id      = data.aws_vpc.platform.id

  egress {
    from_port   = 443
    to_port     = 443
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
    description = "HTTPS outbound for SSM Agent"
  }

  tags = {
    Name = "sg-ec2-ssm-platform"
  }
}

# ── EC2 Instance ──────────────────────────────────────────────────────────────
# Deployed into a private subnet.
# No key pair — access via SSM Session Manager only.
# t3.micro stays within free tier for validation purposes.

resource "aws_instance" "platform" {
  ami                    = data.aws_ami.amazon_linux_2.id
  instance_type          = var.instance_type
  subnet_id              = data.aws_subnets.private.ids[0]
  iam_instance_profile   = aws_iam_instance_profile.ec2_ssm.name
  vpc_security_group_ids = [aws_security_group.ec2_ssm.id]

  # No key pair — SSM only
  key_name = null

  metadata_options {
    http_endpoint               = "enabled"
    http_tokens                 = "required"
    http_put_response_hop_limit = 1
  }

  root_block_device {
    volume_type           = "gp3"
    volume_size           = 8
    delete_on_termination = true
    encrypted             = true
  }

  tags = {
    Name = "ec2-platform-validation"
  }
}
