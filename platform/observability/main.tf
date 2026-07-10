# ── SNS Topic — Alert Notifications ──────────────────────────────────────────
# Central notification channel for all platform alerts.
# Equivalent of Azure Action Group — receives alerts and fans out
# to subscribers. Email subscription confirmed manually after apply.

resource "aws_sns_topic" "platform_alerts" {
  name = "stratum-platform-alerts"
}

resource "aws_sns_topic_subscription" "email" {
  topic_arn = aws_sns_topic.platform_alerts.arn
  protocol  = "email"
  endpoint  = var.alert_email
}

# ── CloudWatch Log Groups ─────────────────────────────────────────────────────
# Separate log group per concern — AWS pushes logs to isolated groups.
# Retention enforced on each group to control cost.
# 30 days balances operational debugging window against storage cost.

resource "aws_cloudwatch_log_group" "application" {
  name              = "/stratum/application"
  retention_in_days = var.log_retention_days
}

resource "aws_cloudwatch_log_group" "platform" {
  name              = "/stratum/platform"
  retention_in_days = var.log_retention_days
}

resource "aws_cloudwatch_log_group" "ec2" {
  name              = "/stratum/ec2"
  retention_in_days = var.log_retention_days
}

# ── CloudTrail ────────────────────────────────────────────────────────────────
# Audit log of every AWS API call in the account.
# Equivalent of Azure Activity Logs — who did what, when, from where.
# Stored in S3 for long-term retention and compliance.
# Critical for post-incident analysis after flash sale events.

resource "aws_s3_bucket" "cloudtrail" {
  bucket = "stratum-cloudtrail-${data.aws_caller_identity.current.account_id}"
}

resource "aws_s3_bucket_public_access_block" "cloudtrail" {
  bucket = aws_s3_bucket.cloudtrail.id

  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

resource "aws_s3_bucket_server_side_encryption_configuration" "cloudtrail" {
  bucket = aws_s3_bucket.cloudtrail.id

  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "AES256"
    }
  }
}

resource "aws_s3_bucket_lifecycle_configuration" "cloudtrail" {
  bucket = aws_s3_bucket.cloudtrail.id

  rule {
    id     = "expire-old-trails"
    status = "Enabled"

    filter {
      prefix = ""
    }

    expiration {
      days = 90
    }
  }
}

data "aws_caller_identity" "current" {}

data "aws_iam_policy_document" "cloudtrail_bucket_policy" {

  statement {
    sid    = "AllowTerraformRole"
    effect = "Allow"

    principals {
      type = "AWS"
      identifiers = [
        "arn:aws:iam::${data.aws_caller_identity.current.account_id}:role/role-terraform-aws-landing-zone"
      ]
    }

    actions = ["s3:*"]
    resources = [
      aws_s3_bucket.cloudtrail.arn,
      "${aws_s3_bucket.cloudtrail.arn}/*"
    ]
  }

  statement {
    sid    = "AWSCloudTrailAclCheck"
    effect = "Allow"

    principals {
      type        = "Service"
      identifiers = ["cloudtrail.amazonaws.com"]
    }

    actions   = ["s3:GetBucketAcl"]
    resources = [aws_s3_bucket.cloudtrail.arn]
  }

  statement {
    sid    = "AWSCloudTrailWrite"
    effect = "Allow"

    principals {
      type        = "Service"
      identifiers = ["cloudtrail.amazonaws.com"]
    }

    actions   = ["s3:PutObject"]
    resources = ["${aws_s3_bucket.cloudtrail.arn}/AWSLogs/${data.aws_caller_identity.current.account_id}/*"]

    condition {
      test     = "StringEquals"
      variable = "s3:x-amz-acl"
      values   = ["bucket-owner-full-control"]
    }
  }
}

resource "aws_s3_bucket_policy" "cloudtrail" {
  bucket = aws_s3_bucket.cloudtrail.id
  policy = data.aws_iam_policy_document.cloudtrail_bucket_policy.json
}

resource "aws_cloudtrail" "platform" {
  name                          = "stratum-platform-trail"
  s3_bucket_name                = aws_s3_bucket.cloudtrail.id
  include_global_service_events = true
  is_multi_region_trail         = false
  enable_log_file_validation    = true

  cloud_watch_logs_group_arn = "${aws_cloudwatch_log_group.platform.arn}:*"
  cloud_watch_logs_role_arn  = aws_iam_role.cloudtrail_cloudwatch.arn

  depends_on = [aws_s3_bucket_policy.cloudtrail]
}

# ── CloudTrail to CloudWatch IAM Role ────────────────────────────────────────
# CloudTrail needs permission to write to CloudWatch Logs.
# Service role pattern — AWS service assumes a role to perform actions
# on your behalf. Same pattern as EC2 instance profile.

data "aws_iam_policy_document" "cloudtrail_trust" {
  statement {
    effect  = "Allow"
    actions = ["sts:AssumeRole"]

    principals {
      type        = "Service"
      identifiers = ["cloudtrail.amazonaws.com"]
    }
  }
}

data "aws_iam_policy_document" "cloudtrail_cloudwatch_permissions" {
  statement {
    sid    = "CloudTrailCreateLogStream"
    effect = "Allow"
    actions = [
      "logs:CreateLogStream",
      "logs:PutLogEvents"
    ]
    resources = ["${aws_cloudwatch_log_group.platform.arn}:*"]
  }
}

resource "aws_iam_role" "cloudtrail_cloudwatch" {
  name               = "role-cloudtrail-cloudwatch-platform"
  assume_role_policy = data.aws_iam_policy_document.cloudtrail_trust.json
  description        = "Allows CloudTrail to write logs to CloudWatch"
}

resource "aws_iam_role_policy" "cloudtrail_cloudwatch" {
  name   = "cloudtrail-cloudwatch-permissions"
  role   = aws_iam_role.cloudtrail_cloudwatch.id
  policy = data.aws_iam_policy_document.cloudtrail_cloudwatch_permissions.json
}

# ── CloudWatch Alarms ─────────────────────────────────────────────────────────
# Three alarms covering the flash sale visibility gap:
#
# 1. EC2 CPU — detects compute saturation during traffic spikes
# 2. EC2 Status Check — detects instance health failures
# 3. Estimated charges — budget protection, alerts before cost overrun
#
# All route to SNS topic → email notification.

data "aws_instance" "platform" {
  filter {
    name   = "tag:Name"
    values = ["ec2-platform-validation"]
  }
}

resource "aws_cloudwatch_metric_alarm" "ec2_cpu_high" {
  alarm_name          = "stratum-ec2-cpu-high"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = 2
  metric_name         = "CPUUtilization"
  namespace           = "AWS/EC2"
  period              = 300
  statistic           = "Average"
  threshold           = 80
  alarm_description   = "EC2 CPU utilisation above 80% for 10 minutes"
  alarm_actions       = [aws_sns_topic.platform_alerts.arn]
  ok_actions          = [aws_sns_topic.platform_alerts.arn]

  dimensions = {
    InstanceId = data.aws_instance.platform.id
  }
}

resource "aws_cloudwatch_metric_alarm" "ec2_status_check" {
  alarm_name          = "stratum-ec2-status-check"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = 2
  metric_name         = "StatusCheckFailed"
  namespace           = "AWS/EC2"
  period              = 60
  statistic           = "Maximum"
  threshold           = 0
  alarm_description   = "EC2 instance status check failed"
  alarm_actions       = [aws_sns_topic.platform_alerts.arn]

  dimensions = {
    InstanceId = data.aws_instance.platform.id
  }
}

resource "aws_cloudwatch_metric_alarm" "estimated_charges" {
  alarm_name          = "stratum-estimated-charges"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = 1
  metric_name         = "EstimatedCharges"
  namespace           = "AWS/Billing"
  period              = 86400
  statistic           = "Maximum"
  threshold           = 8
  alarm_description   = "Estimated AWS charges exceed $8"
  alarm_actions       = [aws_sns_topic.platform_alerts.arn]

  dimensions = {
    Currency = "USD"
  }
}


