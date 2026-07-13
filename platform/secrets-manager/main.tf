# ── Data Sources ──────────────────────────────────────────────────────────────

data "aws_caller_identity" "current" {}

# ── Platform Database Secret ──────────────────────────────────────────────────
# Placeholder secret for Phase 4 database credentials.
# Applications retrieve this at runtime — no credentials in code or
# environment variables. Pattern mirrors Azure Key Vault usage in
# taskflow-platform.
#
# Secret value is set outside Terraform — Terraform manages the secret
# resource and its access policy, not the secret value itself.
# Storing sensitive values in Terraform state is a security anti-pattern.

resource "aws_secretsmanager_secret" "database" {
  name                    = "stratum/platform/database"
  description             = "Platform database credentials for Stratum application layer"
  recovery_window_in_days = var.recovery_window_days

  tags = {
    Name = "stratum-platform-database"
  }
}

resource "aws_secretsmanager_secret" "app_config" {
  name                    = "stratum/platform/app-config"
  description             = "Application configuration secrets for Stratum platform"
  recovery_window_in_days = var.recovery_window_days

  tags = {
    Name = "stratum-platform-app-config"
  }
}

# ── Secret Resource Policy ────────────────────────────────────────────────────
# Controls which identities can read the secret.
# EC2 instance profile role granted read access — instances retrieve
# credentials at runtime via the Secrets Manager API.
# Terraform role granted manage access for lifecycle operations.
#
# Pattern: resource-based policy + IAM policy must both allow access.
# Same dual-layer evaluation as S3 bucket policies.

data "aws_iam_policy_document" "database_secret_policy" {
  statement {
    sid    = "AllowTerraformRole"
    effect = "Allow"

    principals {
      type        = "AWS"
      identifiers = ["arn:aws:iam::${data.aws_caller_identity.current.account_id}:role/role-terraform-aws-landing-zone"]
    }

    actions   = ["secretsmanager:*"]
    resources = ["*"]
  }

  statement {
    sid    = "AllowEC2SSMRole"
    effect = "Allow"

    principals {
      type        = "AWS"
      identifiers = ["arn:aws:iam::${data.aws_caller_identity.current.account_id}:role/role-ec2-ssm-platform"]
    }

    actions = [
      "secretsmanager:GetSecretValue",
      "secretsmanager:DescribeSecret"
    ]
    resources = ["*"]
  }
}

resource "aws_secretsmanager_secret_policy" "database" {
  secret_arn = aws_secretsmanager_secret.database.arn
  policy     = data.aws_iam_policy_document.database_secret_policy.json
}

resource "aws_secretsmanager_secret_policy" "app_config" {
  secret_arn = aws_secretsmanager_secret.app_config.arn
  policy     = data.aws_iam_policy_document.database_secret_policy.json
}
