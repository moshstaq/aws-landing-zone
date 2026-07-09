resource "random_string" "suffix" {
  length  = 6
  special = false
  upper   = false
}

# ── Application S3 Bucket ─────────────────────────────────────────────────────
# General purpose application storage for Stratum Retail Group.
# Stores diagnostic data, access logs, and static assets.
# Lifecycle rules control cost by transitioning and expiring objects
# automatically — critical for flash sale event data that loses value
# over time.

resource "aws_s3_bucket" "application" {
  bucket = "stratum-application-${random_string.suffix.result}"
}

resource "aws_s3_bucket_versioning" "application" {
  bucket = aws_s3_bucket.application.id

  versioning_configuration {
    status = "Enabled"
  }
}

resource "aws_s3_bucket_server_side_encryption_configuration" "application" {
  bucket = aws_s3_bucket.application.id

  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "AES256"
    }
  }
}

resource "aws_s3_bucket_public_access_block" "application" {
  bucket = aws_s3_bucket.application.id

  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

# ── Lifecycle Rules ───────────────────────────────────────────────────────────
# Two rules covering the diagnostic data lifecycle:
#
# Rule 1 — diagnostic-logs: transitions logs to Standard-IA after 30 days
# (infrequent access tier, ~58% cheaper than Standard), then expires after
# 90 days. Flash sale logs are analysed immediately post-event. After 30
# days they are rarely accessed. After 90 days they have no operational value.
#
# Rule 2 — expire-old-versions: removes non-current object versions after
# 30 days. Versioning is enabled for recovery purposes but old versions
# accumulate cost if not expired.

resource "aws_s3_bucket_lifecycle_configuration" "application" {
  bucket = aws_s3_bucket.application.id

  rule {
    id     = "diagnostic-logs"
    status = "Enabled"

    filter {
      prefix = "logs/"
    }

    transition {
      days          = var.transition_to_ia_days
      storage_class = "STANDARD_IA"
    }

    expiration {
      days = var.log_retention_days
    }
  }

  rule {
    id     = "expire-old-versions"
    status = "Enabled"

    filter {
      prefix = ""
    }

    noncurrent_version_expiration {
      noncurrent_days = 30
    }
  }
}

# ── S3 Bucket Policy ──────────────────────────────────────────────────────────
# Enforces encrypted transport — denies any request not using HTTPS.
# Prevents credentials or data being transmitted in plaintext.

data "aws_iam_policy_document" "application_bucket_policy" {
  statement {
    sid    = "AllowTerraformRole"
    effect = "Allow"

    principals {
      type        = "AWS"
      identifiers = ["arn:aws:iam::688365520256:role/role-terraform-aws-landing-zone"]
    }

    actions = ["s3:*"]
    resources = [
      aws_s3_bucket.application.arn,
      "${aws_s3_bucket.application.arn}/*"
    ]
  }

  statement {
    sid    = "DenyNonHTTPS"
    effect = "Deny"

    principals {
      type        = "*"
      identifiers = ["*"]
    }

    actions = ["s3:*"]
    resources = [
      aws_s3_bucket.application.arn,
      "${aws_s3_bucket.application.arn}/*"
    ]

    condition {
      test     = "Bool"
      variable = "aws:SecureTransport"
      values   = ["false"]
    }
  }
}

resource "aws_s3_bucket_policy" "application" {
  bucket = aws_s3_bucket.application.id
  policy = data.aws_iam_policy_document.application_bucket_policy.json
}


