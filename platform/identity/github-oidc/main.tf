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
      "s3:GetBucketRequestPayment",
      "s3:HeadBucket",
      "s3:HeadObject",
      "s3:GetBucketAcl",
      "s3:GetBucketCORS",
      "s3:GetBucketLogging",
      "s3:GetBucketObjectLockConfiguration",
      "s3:GetBucketReplication",
      "s3:GetBucketWebsite",
      "s3:GetAccelerateConfiguration"
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

data "aws_iam_policy_document" "terraform_ecr" {
  statement {
    sid    = "ECRManagement"
    effect = "Allow"
    actions = [
      "ecr:GetAuthorizationToken",
      "ecr:CreateRepository",
      "ecr:DeleteRepository",
      "ecr:DescribeRepositories",
      "ecr:GetRepositoryPolicy",
      "ecr:SetRepositoryPolicy",
      "ecr:DeleteRepositoryPolicy",
      "ecr:PutLifecyclePolicy",
      "ecr:GetLifecyclePolicy",
      "ecr:DeleteLifecyclePolicy",
      "ecr:ListTagsForResource",
      "ecr:TagResource",
      "ecr:UntagResource",
      "ecr:PutImageTagMutability",
      "ecr:PutImageScanningConfiguration",
      "ecr:GetRegistryPolicy",
      "ecr:DescribeRegistry",
      "ecr:BatchGetImage",
      "ecr:BatchCheckLayerAvailability",
      "ecr:GetDownloadUrlForLayer",
      "ecr:InitiateLayerUpload",
      "ecr:UploadLayerPart",
      "ecr:CompleteLayerUpload",
      "ecr:PutImage"
    ]
    resources = ["*"]
  }
}

resource "aws_iam_role_policy" "terraform_ecr" {
  name   = "terraform-ecr-management"
  role   = aws_iam_role.terraform.id
  policy = data.aws_iam_policy_document.terraform_ecr.json
}

data "aws_iam_policy_document" "terraform_observability" {
  statement {
    sid    = "CloudWatchManagement"
    effect = "Allow"
    actions = [
      "cloudwatch:PutMetricAlarm",
      "cloudwatch:DeleteAlarms",
      "cloudwatch:DescribeAlarms",
      "cloudwatch:GetMetricStatistics",
      "cloudwatch:ListMetrics",
      "cloudwatch:PutDashboard",
      "cloudwatch:DeleteDashboards",
      "cloudwatch:GetDashboard"
    ]
    resources = ["*"]
  }

  statement {
    sid    = "CloudWatchLogsManagement"
    effect = "Allow"
    actions = [
      "logs:CreateLogGroup",
      "logs:DeleteLogGroup",
      "logs:DescribeLogGroups",
      "logs:PutRetentionPolicy",
      "logs:DeleteRetentionPolicy",
      "logs:ListTagsLogGroup",
      "logs:TagLogGroup",
      "logs:UntagLogGroup",
      "logs:AssociateKmsKey",
      "logs:CreateLogStream",
      "logs:PutLogEvents",
      "logs:DescribeLogStreams"
    ]
    resources = ["*"]
  }

  statement {
    sid    = "CloudTrailManagement"
    effect = "Allow"
    actions = [
      "cloudtrail:CreateTrail",
      "cloudtrail:DeleteTrail",
      "cloudtrail:GetTrail",
      "cloudtrail:GetTrailStatus",
      "cloudtrail:DescribeTrails",
      "cloudtrail:StartLogging",
      "cloudtrail:StopLogging",
      "cloudtrail:UpdateTrail",
      "cloudtrail:ListTags",
      "cloudtrail:AddTags",
      "cloudtrail:RemoveTags",
      "cloudtrail:GetEventSelectors",
      "cloudtrail:PutEventSelectors"
    ]
    resources = ["*"]
  }

  statement {
    sid    = "SNSManagement"
    effect = "Allow"
    actions = [
      "sns:CreateTopic",
      "sns:DeleteTopic",
      "sns:GetTopicAttributes",
      "sns:SetTopicAttributes",
      "sns:Subscribe",
      "sns:Unsubscribe",
      "sns:GetSubscriptionAttributes",
      "sns:ListSubscriptionsByTopic",
      "sns:ListTopics",
      "sns:TagResource",
      "sns:UntagResource",
      "sns:ListTagsForResource"
    ]
    resources = ["*"]
  }
}

resource "aws_iam_role_policy" "terraform_observability" {
  name   = "terraform-observability-management"
  role   = aws_iam_role.terraform.id
  policy = data.aws_iam_policy_document.terraform_observability.json
}


data "aws_iam_policy_document" "terraform_compute_scaling" {
  statement {
    sid    = "ELBManagement"
    effect = "Allow"
    actions = [
      "elasticloadbalancing:CreateLoadBalancer",
      "elasticloadbalancing:DeleteLoadBalancer",
      "elasticloadbalancing:DescribeLoadBalancers",
      "elasticloadbalancing:DescribeLoadBalancerAttributes",
      "elasticloadbalancing:ModifyLoadBalancerAttributes",
      "elasticloadbalancing:CreateTargetGroup",
      "elasticloadbalancing:DeleteTargetGroup",
      "elasticloadbalancing:DescribeTargetGroups",
      "elasticloadbalancing:DescribeTargetGroupAttributes",
      "elasticloadbalancing:ModifyTargetGroup",
      "elasticloadbalancing:ModifyTargetGroupAttributes",
      "elasticloadbalancing:CreateListener",
      "elasticloadbalancing:DeleteListener",
      "elasticloadbalancing:DescribeListeners",
      "elasticloadbalancing:ModifyListener",
      "elasticloadbalancing:RegisterTargets",
      "elasticloadbalancing:DeregisterTargets",
      "elasticloadbalancing:DescribeTargetHealth",
      "elasticloadbalancing:AddTags",
      "elasticloadbalancing:RemoveTags",
      "elasticloadbalancing:DescribeTags"
    ]
    resources = ["*"]
  }

  statement {
    sid    = "AutoScalingManagement"
    effect = "Allow"
    actions = [
      "autoscaling:CreateAutoScalingGroup",
      "autoscaling:DeleteAutoScalingGroup",
      "autoscaling:DescribeAutoScalingGroups",
      "autoscaling:UpdateAutoScalingGroup",
      "autoscaling:CreateLaunchConfiguration",
      "autoscaling:DeleteLaunchConfiguration",
      "autoscaling:DescribeLaunchConfigurations",
      "autoscaling:PutScalingPolicy",
      "autoscaling:DeletePolicy",
      "autoscaling:DescribePolicies",
      "autoscaling:DescribeScalingActivities",
      "autoscaling:DescribeAutoScalingInstances",
      "autoscaling:TerminateInstanceInAutoScalingGroup",
      "autoscaling:SetDesiredCapacity",
      "autoscaling:DescribeLifecycleHooks",
      "autoscaling:DescribeNotificationConfigurations",
      "autoscaling:DescribeTags",
      "autoscaling:CreateOrUpdateTags",
      "autoscaling:DeleteTags"
    ]
    resources = ["*"]
  }

  statement {
    sid    = "LaunchTemplateManagement"
    effect = "Allow"
    actions = [
      "ec2:CreateLaunchTemplate",
      "ec2:DeleteLaunchTemplate",
      "ec2:DescribeLaunchTemplates",
      "ec2:DescribeLaunchTemplateVersions",
      "ec2:CreateLaunchTemplateVersion",
      "ec2:DeleteLaunchTemplateVersions",
      "ec2:ModifyLaunchTemplate",
      "ec2:RunInstances",
      "ec2:TerminateInstances",
      "ec2:DescribeInstanceTypes"
    ]
    resources = ["*"]
  }
}

resource "aws_iam_role_policy" "terraform_compute_scaling" {
  name   = "terraform-compute-scaling-management"
  role   = aws_iam_role.terraform.id
  policy = data.aws_iam_policy_document.terraform_compute_scaling.json
}

data "aws_iam_policy_document" "terraform_secrets" {
  statement {
    sid    = "SecretsManagerManagement"
    effect = "Allow"
    actions = [
      "secretsmanager:CreateSecret",
      "secretsmanager:DeleteSecret",
      "secretsmanager:DescribeSecret",
      "secretsmanager:GetSecretValue",
      "secretsmanager:ListSecrets",
      "secretsmanager:PutSecretValue",
      "secretsmanager:RestoreSecret",
      "secretsmanager:TagResource",
      "secretsmanager:UntagResource",
      "secretsmanager:UpdateSecret",
      "secretsmanager:GetResourcePolicy",
      "secretsmanager:PutResourcePolicy",
      "secretsmanager:DeleteResourcePolicy"
    ]
    resources = ["*"]
  }
}

resource "aws_iam_role_policy" "terraform_secrets" {
  name   = "terraform-secrets-management"
  role   = aws_iam_role.terraform.id
  policy = data.aws_iam_policy_document.terraform_secrets.json
}

data "aws_iam_policy_document" "terraform_eks" {
  statement {
    sid    = "EKSManagement"
    effect = "Allow"
    actions = [
      "eks:CreateCluster",
      "eks:DeleteCluster",
      "eks:DescribeCluster",
      "eks:ListClusters",
      "eks:UpdateClusterConfig",
      "eks:UpdateClusterVersion",
      "eks:CreateNodegroup",
      "eks:DeleteNodegroup",
      "eks:DescribeNodegroup",
      "eks:ListNodegroups",
      "eks:UpdateNodegroupConfig",
      "eks:UpdateNodegroupVersion",
      "eks:TagResource",
      "eks:UntagResource",
      "eks:ListTagsForResource",
      "eks:AssociateIdentityProviderConfig",
      "eks:DescribeIdentityProviderConfig",
      "eks:DisassociateIdentityProviderConfig",
      "eks:ListIdentityProviderConfigs"
    ]
    resources = ["*"]
  }

  statement {
    sid    = "TLSCertificate"
    effect = "Allow"
    actions = [
      "iam:GetOpenIDConnectProvider",
      "iam:CreateOpenIDConnectProvider",
      "iam:DeleteOpenIDConnectProvider",
      "iam:TagOpenIDConnectProvider"
    ]
    resources = ["*"]
  }
}

resource "aws_iam_role_policy" "terraform_eks" {
  name   = "terraform-eks-management"
  role   = aws_iam_role.terraform.id
  policy = data.aws_iam_policy_document.terraform_eks.json
}


# ── Stratum Platform — GitHub Actions Role ────────────────────────────────────
# Separate identity for stratum-platform repository.
# Consumer role — reads data sources and provisions workload environments.
# Cannot manage platform foundation resources.

data "aws_iam_policy_document" "stratum_platform_trust" {
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
      values   = ["repo:${var.github_org}/stratum-platform:*"]
    }
  }
}

resource "aws_iam_role" "stratum_platform_github" {
  name               = "role-github-actions-stratum-platform"
  assume_role_policy = data.aws_iam_policy_document.stratum_platform_trust.json
  description        = "Assumed by GitHub Actions via OIDC for stratum-platform"
}

# ── Stratum Platform — Provisioning Role ──────────────────────────────────────
# Separate provisioning role for stratum-platform.
# Scoped to consumer operations — data source reads, workload environment
# provisioning. Cannot modify platform foundation infrastructure.

data "aws_iam_policy_document" "stratum_platform_provisioning_trust" {
  statement {
    effect = "Allow"
    actions = [
      "sts:AssumeRole",
      "sts:TagSession"
    ]

    principals {
      type        = "AWS"
      identifiers = [aws_iam_role.stratum_platform_github.arn]
    }
  }
}

resource "aws_iam_role" "stratum_platform_terraform" {
  name               = "role-terraform-stratum-platform"
  assume_role_policy = data.aws_iam_policy_document.stratum_platform_provisioning_trust.json
  description        = "Assumed by Terraform for stratum-platform resource provisioning"
}

# ── GitHub Actions → Provisioning Role Permission ─────────────────────────────

data "aws_iam_policy_document" "stratum_platform_github_permissions" {
  statement {
    effect    = "Allow"
    actions   = ["sts:AssumeRole"]
    resources = [aws_iam_role.stratum_platform_terraform.arn]
  }

  statement {
    effect    = "Allow"
    actions   = ["sts:TagSession"]
    resources = ["*"]
  }
}

resource "aws_iam_role_policy" "stratum_platform_github" {
  name   = "assume-terraform-role"
  role   = aws_iam_role.stratum_platform_github.id
  policy = data.aws_iam_policy_document.stratum_platform_github_permissions.json
}

# ── Stratum Platform — Consumer Permissions ───────────────────────────────────
# Read-only on platform resources + write on workload boundaries.

data "aws_iam_policy_document" "stratum_platform_permissions" {
  statement {
    sid    = "ReadPlatformResources"
    effect = "Allow"
    actions = [
      "ec2:DescribeVpcs",
      "ec2:DescribeSubnets",
      "ec2:DescribeSecurityGroups",
      "ec2:DescribeInternetGateways",
      "ec2:DescribeRouteTables",
      "ec2:DescribeVpcEndpoints",
      "ec2:DescribeAvailabilityZones",
      "ec2:DescribeAccountAttributes",
      "ecr:DescribeRepositories",
      "ecr:ListImages",
      "sns:GetTopicAttributes",
      "sns:ListTopics",
      "logs:DescribeLogGroups",
      "secretsmanager:DescribeSecret",
      "secretsmanager:ListSecrets",
      "eks:DescribeCluster",
      "ec2:DescribeVpcAttribute",
      "ecr:DescribeImages",
      "logs:ListTagsLogGroup",
      "secretsmanager:GetResourcePolicy",
      "eks:ListClusters"
    ]
    resources = ["*"]
  }

  statement {
    sid    = "WorkloadEnvironmentProvisioning"
    effect = "Allow"
    actions = [
      "iam:CreateRole",
      "iam:DeleteRole",
      "iam:GetRole",
      "iam:ListRolePolicies",
      "iam:ListAttachedRolePolicies",
      "iam:PutRolePolicy",
      "iam:DeleteRolePolicy",
      "iam:GetRolePolicy",
      "iam:PassRole",
      "iam:TagRole",
      "iam:UntagRole",
      "ec2:CreateSecurityGroup",
      "ec2:DeleteSecurityGroup",
      "ec2:AuthorizeSecurityGroupEgress",
      "ec2:RevokeSecurityGroupEgress",
      "ec2:CreateTags",
      "ec2:DeleteTags",
      "s3:CreateBucket",
      "s3:DeleteBucket",
      "s3:GetBucketPolicy",
      "s3:PutBucketPolicy",
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
      "s3:GetBucketLocation",
      "s3:GetBucketAcl",
      "s3:HeadBucket",
      "s3:ListAllMyBuckets",
      "ecr:CreateRepository",
      "ecr:DeleteRepository",
      "ecr:PutLifecyclePolicy",
      "ecr:GetLifecyclePolicy",
      "ecr:DeleteLifecyclePolicy",
      "ecr:PutImageTagMutability",
      "ecr:PutImageScanningConfiguration",
      "ecr:GetRepositoryPolicy",
      "ecr:SetRepositoryPolicy",
      "ecr:DeleteRepositoryPolicy",
      "ecr:ListTagsForResource",
      "ecr:TagResource",
      "ecr:UntagResource"
    ]
    resources = ["*"]
  }

  statement {
    sid    = "StateBackendAccess"
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
    sid    = "StateLocking"
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

resource "aws_iam_role_policy" "stratum_platform_terraform" {
  name   = "stratum-platform-permissions"
  role   = aws_iam_role.stratum_platform_terraform.id
  policy = data.aws_iam_policy_document.stratum_platform_permissions.json
}


# ── EKS Node Role ─────────────────────────────────────────────────────────────
# Centralised in identity for auditability. Every IAM role and its
# policies are visible from one module.
# Created independently of EKS — the role persists even when the
# cluster is destroyed between sessions for cost management.

data "aws_iam_policy_document" "eks_node_trust" {
  statement {
    effect  = "Allow"
    actions = ["sts:AssumeRole"]

    principals {
      type        = "Service"
      identifiers = ["ec2.amazonaws.com"]
    }
  }
}

resource "aws_iam_role" "eks_node" {
  name               = "role-eks-node-platform"
  assume_role_policy = data.aws_iam_policy_document.eks_node_trust.json
  description        = "EKS worker node role"
}

resource "aws_iam_role_policy_attachment" "eks_worker_node_policy" {
  role       = aws_iam_role.eks_node.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonEKSWorkerNodePolicy"
}

resource "aws_iam_role_policy_attachment" "eks_cni_policy" {
  role       = aws_iam_role.eks_node.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonEKS_CNI_Policy"
}

resource "aws_iam_role_policy_attachment" "eks_ecr_readonly" {
  role       = aws_iam_role.eks_node.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonEC2ContainerRegistryReadOnly"
}

resource "aws_iam_role_policy_attachment" "eks_cloudwatch_agent" {
  role       = aws_iam_role.eks_node.name
  policy_arn = "arn:aws:iam::aws:policy/CloudWatchAgentServerPolicy"
}


# ── EKS Cluster Role ─────────────────────────────────────────────────────────────
# Centralised in identity for auditability. Every IAM role and its policies are visible from one module.
# Created independently of EKS — the role persists even when the cluster is destroyed between sessions for cost management.

data "aws_iam_policy_document" "eks_cluster_trust" {
  statement {
    effect  = "Allow"
    actions = ["sts:AssumeRole"]

    principals {
      type        = "Service"
      identifiers = ["eks.amazonaws.com"]
    }
  }
}

resource "aws_iam_role" "eks_cluster" {
  name               = "role-eks-cluster-platform"
  assume_role_policy = data.aws_iam_policy_document.eks_cluster_trust.json
  description        = "EKS cluster role allows control plane to manage AWS resources"
}

resource "aws_iam_role_policy_attachment" "eks_cluster_policy" {
  role       = aws_iam_role.eks_cluster.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonEKSClusterPolicy"
}
