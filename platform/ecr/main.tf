# ── ECR Repository ────────────────────────────────────────────────────────────
# Central container registry for Stratum platform workloads.
# Stores application images consumed by EKS in Phase 2.
# Built in Phase 1 so the registry exists before container work begins —
# same pattern as ACR in azure-landing-zone.

resource "aws_ecr_repository" "platform" {
  name                 = "stratum-platform"
  image_tag_mutability = "IMMUTABLE"

  image_scanning_configuration {
    scan_on_push = true
  }

  encryption_configuration {
    encryption_type = "AES256"
  }
}

# ── Lifecycle Policy ──────────────────────────────────────────────────────────
# Retains only the most recent images per tag prefix.
# Prevents unbounded image accumulation which drives storage cost.
# Pattern mirrors S3 lifecycle rules — automated expiry of objects
# that have outlived their operational value.

resource "aws_ecr_lifecycle_policy" "platform" {
  repository = aws_ecr_repository.platform.name

  policy = jsonencode({
    rules = [
      {
        rulePriority = 1
        description  = "Retain only the last ${var.image_retention_count} images"
        selection = {
          tagStatus   = "any"
          countType   = "imageCountMoreThan"
          countNumber = var.image_retention_count
        }
        action = {
          type = "expire"
        }
      }
    ]
  })
}

# ── Repository Policy ─────────────────────────────────────────────────────────
# Grants the Terraform provisioning role push and pull access.
# EKS node role will be added in Phase 2 when the cluster exists.

data "aws_caller_identity" "current" {}

data "aws_iam_policy_document" "ecr_policy" {
  statement {
    sid    = "AllowTerraformRole"
    effect = "Allow"

    principals {
      type = "AWS"
      identifiers = [
        "arn:aws:iam::${data.aws_caller_identity.current.account_id}:role/role-terraform-aws-landing-zone"
      ]
    }

    actions = [
      "ecr:GetDownloadUrlForLayer",
      "ecr:BatchGetImage",
      "ecr:BatchCheckLayerAvailability",
      "ecr:PutImage",
      "ecr:InitiateLayerUpload",
      "ecr:UploadLayerPart",
      "ecr:CompleteLayerUpload",
      "ecr:DescribeRepositories",
      "ecr:GetRepositoryPolicy",
      "ecr:ListImages",
      "ecr:DeleteRepository",
      "ecr:BatchDeleteImage",
      "ecr:SetRepositoryPolicy",
      "ecr:DeleteRepositoryPolicy"
    ]
  }
}

resource "aws_ecr_repository_policy" "platform" {
  repository = aws_ecr_repository.platform.name
  policy     = data.aws_iam_policy_document.ecr_policy.json
}
