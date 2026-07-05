# ── GitHub OIDC Identity Provider ─────────────────────────────────────────────
# Registers GitHub's OIDC issuer with this AWS account.
# One provider per account — all repositories share this registration.

resource "aws_iam_openid_connect_provider" "github" {
  url = "https://token.actions.githubusercontent.com"

  client_id_list = [
    "sts.amazonaws.com"
  ]

  thumbprint_list = [
    "6938fd4d98bab03faadb97b34396831e3780aea1",
    "1c58a3a8518e8759bf075b76b750d4f2df264fcd"
  ]
}

# ── GitHub Actions IAM Role ───────────────────────────────────────────────────
# Assumed by the CI runner via OIDC token exchange.
# Scoped to moshstaq/aws-landing-zone only.
# Only permission is to assume the Terraform provisioning role.

data "aws_iam_policy_document" "github_actions_trust" {
  statement {
    effect  = "Allow"
    actions = ["sts:AssumeRoleWithWebIdentity"]

    principals {
      type        = "Federated"
      identifiers = [aws_iam_openid_connect_provider.github.arn]
    }

    condition {
      test     = "StringEquals"
      variable = "token.actions.githubusercontent.com:aud"
      values   = ["sts.amazonaws.com"]
    }

    condition {
      test     = "StringLike"
      variable = "token.actions.githubusercontent.com:sub"
      values   = ["repo:${var.github_org}/${var.github_repo}:*"]
    }
  }
}

resource "aws_iam_role" "github_actions" {
  name               = "role-github-actions-aws-landing-zone"
  assume_role_policy = data.aws_iam_policy_document.github_actions_trust.json
  description        = "Assumed by GitHub Actions via OIDC for aws-landing-zone"
}

# ── GitHub Actions Permission Policy ─────────────────────────────────────────
# Only permission is sts:AssumeRole on the Terraform provisioning role.
# The CI runner cannot provision resources directly.

data "aws_iam_policy_document" "github_actions_permissions" {
  statement {
    effect    = "Allow"
    actions   = ["sts:AssumeRole"]
    resources = [aws_iam_role.terraform.arn]
  }
}

resource "aws_iam_role_policy" "github_actions" {
  name   = "assume-terraform-role"
  role   = aws_iam_role.github_actions.id
  policy = data.aws_iam_policy_document.github_actions_permissions.json
}

# ── Terraform Provisioning IAM Role ──────────────────────────────────────────
# Assumed by Terraform via the GitHub Actions role.
# This is the identity that actually provisions AWS resources.
# Equivalent of sp-terraform on Azure but without a client secret.

data "aws_iam_policy_document" "terraform_trust" {
  statement {
    effect  = "Allow"
    actions = ["sts:AssumeRole"]

    principals {
      type        = "AWS"
      identifiers = [aws_iam_role.github_actions.arn]
    }
  }
}

resource "aws_iam_role" "terraform" {
  name               = "role-terraform-aws-landing-zone"
  assume_role_policy = data.aws_iam_policy_document.terraform_trust.json
  description        = "Assumed by Terraform via GitHub Actions role for resource provisioning"
}

# ── Terraform Provisioning Permissions ───────────────────────────────────────
# Scoped to what Phase 1 requires. Expanded as new modules are added.
# Current scope: S3 state backend, DynamoDB locking, IAM management.

data "aws_iam_policy_document" "terraform_permissions" {
  # State backend access
  statement {
    effect = "Allow"
    actions = [
      "s3:GetObject",
      "s3:PutObject",
      "s3:DeleteObject",
      "s3:ListBucket"
    ]
    resources = [
      "arn:aws:s3:::stratum-tfstate-7pbqp4",
      "arn:aws:s3:::stratum-tfstate-7pbqp4/*"
    ]
  }

  # State locking
  statement {
    effect = "Allow"
    actions = [
      "dynamodb:GetItem",
      "dynamodb:PutItem",
      "dynamodb:DeleteItem"
    ]
    resources = [
      "arn:aws:dynamodb:us-east-1:688365520256:table/stratum-tfstate-lock"
    ]
  }

  # IAM management for subsequent modules
  statement {
    effect = "Allow"
    actions = [
      "iam:CreateRole",
      "iam:DeleteRole",
      "iam:GetRole",
      "iam:ListRoles",
      "iam:AttachRolePolicy",
      "iam:DetachRolePolicy",
      "iam:PutRolePolicy",
      "iam:DeleteRolePolicy",
      "iam:GetRolePolicy",
      "iam:CreateOpenIDConnectProvider",
      "iam:DeleteOpenIDConnectProvider",
      "iam:GetOpenIDConnectProvider",
      "iam:TagOpenIDConnectProvider",
      "iam:PassRole"
    ]
    resources = ["*"]
  }
}

resource "aws_iam_role_policy" "terraform" {
  name   = "terraform-provisioning-permissions"
  role   = aws_iam_role.terraform.id
  policy = data.aws_iam_policy_document.terraform_permissions.json
}
