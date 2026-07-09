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
    effect = "Allow"
    actions = [
      "sts:AssumeRole",
      "sts:TagSession"
    ]
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
    effect = "Allow"
    actions = [
      "sts:AssumeRole",
      "sts:TagSession"
    ]

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

# ── Terraform Role — State Backend Policy ─────────────────────────────────────
# Scoped to specific S3 bucket and DynamoDB table.
# No wildcards on resources — least privilege enforced.

data "aws_iam_policy_document" "terraform_state" {
  statement {
    sid    = "S3StateAccess"
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

  statement {
    sid    = "DynamoDBLocking"
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
}

resource "aws_iam_role_policy" "terraform_state" {
  name   = "terraform-state-access"
  role   = aws_iam_role.terraform.id
  policy = data.aws_iam_policy_document.terraform_state.json
}

# ── Terraform Role — IAM Policy ───────────────────────────────────────────────
# Custom policy — IAM actions are sensitive and warrant precise control.
# Resource wildcard unavoidable for IAM but actions are tightly scoped.

data "aws_iam_policy_document" "terraform_iam" {
  statement {
    sid    = "IAMRoleManagement"
    effect = "Allow"
    actions = [
      "iam:CreateRole",
      "iam:DeleteRole",
      "iam:GetRole",
      "iam:ListRoles",
      "iam:ListRolePolicies",
      "iam:ListAttachedRolePolicies",
      "iam:AttachRolePolicy",
      "iam:DetachRolePolicy",
      "iam:PutRolePolicy",
      "iam:DeleteRolePolicy",
      "iam:GetRolePolicy",
      "iam:UpdateAssumeRolePolicy",
      "iam:PassRole",
      "iam:TagRole",
      "iam:UntagRole"
    ]
    resources = ["*"]
  }

  statement {
    sid    = "IAMInstanceProfileManagement"
    effect = "Allow"
    actions = [
      "iam:CreateInstanceProfile",
      "iam:DeleteInstanceProfile",
      "iam:GetInstanceProfile",
      "iam:ListInstanceProfiles",
      "iam:ListInstanceProfilesForRole",
      "iam:AddRoleToInstanceProfile",
      "iam:RemoveRoleFromInstanceProfile",
      "iam:TagInstanceProfile"
    ]
    resources = ["*"]
  }

  statement {
    sid    = "IAMOIDCManagement"
    effect = "Allow"
    actions = [
      "iam:CreateOpenIDConnectProvider",
      "iam:DeleteOpenIDConnectProvider",
      "iam:GetOpenIDConnectProvider",
      "iam:ListOpenIDConnectProviders",
      "iam:TagOpenIDConnectProvider"
    ]
    resources = ["*"]
  }

  statement {
    sid    = "IAMPolicyManagement"
    effect = "Allow"
    actions = [
      "iam:CreatePolicy",
      "iam:DeletePolicy",
      "iam:GetPolicy",
      "iam:GetPolicyVersion",
      "iam:ListPolicies",
      "iam:ListPolicyVersions"
    ]
    resources = ["*"]
  }
}

resource "aws_iam_role_policy" "terraform_iam" {
  name   = "terraform-iam-management"
  role   = aws_iam_role.terraform.id
  policy = data.aws_iam_policy_document.terraform_iam.json
}

# ── Terraform Role — EC2 Policy ───────────────────────────────────────────────
# AWS managed policy — AmazonEC2FullAccess covers all EC2 and networking
# operations needed across Phase 1. Simpler than maintaining a custom
# permission list that grows with every new EC2 feature used.

resource "aws_iam_role_policy_attachment" "terraform_ec2" {
  role       = aws_iam_role.terraform.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonEC2FullAccess"
}


data "aws_iam_policy_document" "terraform_s3" {
  statement {
    sid    = "S3ApplicationBucketManagement"
    effect = "Allow"
    actions = [
      "s3:CreateBucket",
      "s3:DeleteBucket",
      "s3:GetBucketPolicy",
      "s3:PutBucketPolicy",
      "s3:DeleteBucketPolicy",
      "s3:GetBucketVersioning",
      "s3:PutBucketVersioning",
      "s3:GetBucketPublicAccessBlock",
      "s3:PutBucketPublicAccessBlock",
      "s3:GetEncryptionConfiguration",
      "s3:PutEncryptionConfiguration",
      "s3:GetLifecycleConfiguration",
      "s3:PutLifecycleConfiguration",
      "s3:GetBucketTagging",
      "s3:PutBucketTagging",
      "s3:ListAllMyBuckets",
      "s3:GetBucketLocation",
      "s3:GetBucketRequestPayment"
    ]
    resources = ["*"]
  }

  statement {
    sid    = "VPCEndpointManagement"
    effect = "Allow"
    actions = [
      "ec2:CreateVpcEndpoint",
      "ec2:DeleteVpcEndpoints",
      "ec2:DescribeVpcEndpoints",
      "ec2:ModifyVpcEndpoint",
      "ec2:DescribePrefixLists"
    ]
    resources = ["*"]
  }
}

resource "aws_iam_role_policy" "terraform_s3" {
  name   = "terraform-s3-management"
  role   = aws_iam_role.terraform.id
  policy = data.aws_iam_policy_document.terraform_s3.json
}
