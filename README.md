markdown

# AWS Landing Zone

Production-pattern AWS platform foundation for Stratum Retail Group, built with Terraform. This repository provisions the infrastructure that the US-acquired business runs on VPC networking, compute, container platform, observability, and secure identity. Every resource is defined in Terraform, every deployment authenticates via OIDC with no stored credentials, and every architectural decision is documented in an ADR.

[![Terraform](https://img.shields.io/badge/Terraform-1.5+-623CE4?logo=terraform)](https://terraform.io)
[![AWS](https://img.shields.io/badge/AWS-Landing%20Zone-FF9900?logo=amazon-aws)](https://aws.amazon.com)
[![CI/CD](https://img.shields.io/badge/CI%2FCD-GitHub%20Actions-2088FF?logo=github-actions)](https://github.com/features/actions)

---

## Business Context

Stratum Retail Group acquired a US-based retail business running on AWS. The acquisition brought two problems into focus: unpredictable traffic spikes during flash sales were causing the US website to crash and lose revenue, and there was no visibility into system errors or performance bottlenecks across either estate.

This landing zone addresses both. It establishes a production-pattern AWS foundation with elastic compute scaling that absorbs flash sale traffic spikes automatically, and centralised observability that surfaces errors and performance issues before they become incidents.

---

## Architecture

### Network Topology

Internet
│
▼
Application Load Balancer (public subnets)
│
▼
Auto Scaling Group (private subnets)
│
├── EKS Worker Nodes
└── EC2 Validation Instance
│
▼
NAT Gateway → Internet
(outbound only, cost-toggled)

### VPC Design

vpc-platform (10.0.0.0/16)
├── snet-public-us-east-1a (10.0.1.0/24) ← ALB, NAT Gateway
├── snet-public-us-east-1b (10.0.2.0/24) ← ALB (multi-AZ)
├── snet-private-us-east-1a (10.0.10.0/24) ← Compute, EKS nodes
└── snet-private-us-east-1b (10.0.11.0/24) ← Compute, EKS nodes

### Terraform State

Each module owns an isolated state file in S3. No shared state. Cross-module references use AWS data sources exclusively.

stratum-tfstate-7pbqp4 (S3)
├── platform-bootstrap.tfstate
├── platform-github-oidc.tfstate
├── platform-networking.tfstate
├── platform-compute.tfstate
├── platform-storage.tfstate
├── platform-ecr.tfstate
├── platform-observability.tfstate
├── platform-compute-scaling.tfstate
├── platform-secrets-manager.tfstate
└── platform-eks.tfstate

---

## Repository Structure

aws-landing-zone/
├── .github/
│ ├── terraform-modules.json ← module registry
│ └── workflows/
│ ├── terraform-plan.yml ← PR: plan per module
│ ├── terraform-apply.yml ← merge: apply enabled modules
│ └── app-deploy.yml ← app: build and deploy to EKS
│
├── app/
│ └── stratum-service/ ← Go validation service
│ ├── main.go
│ ├── Dockerfile
│ ├── go.mod
│ ├── go.sum
│ └── k8s/ ← Kubernetes manifests
│
├── docs/
│ └── adr/
│ └── ADR-001-phase1-retrospective.md
│
└── platform/
├── bootstrap/ ← tier 0: state backend
├── identity/
│ └── github-oidc/ ← tier 1: OIDC, IAM roles
├── networking/ ← tier 1: VPC, subnets, routing
├── compute/ ← tier 2: EC2, SSM access
├── storage/ ← tier 2: S3 application bucket
├── ecr/ ← tier 2: container registry
├── observability/ ← tier 2: CloudWatch, CloudTrail, SNS
├── compute-scaling/ ← tier 3: ALB, ASG, Launch Template
├── secrets-manager/ ← tier 3: Secrets Manager
└── eks/ ← tier 3: EKS, IRSA

---

## Platform Modules

| Module               | Purpose                                            | CI     | Cost                     |
| -------------------- | -------------------------------------------------- | ------ | ------------------------ |
| bootstrap            | S3 state backend, DynamoDB locking                 | Manual | ~£1/month                |
| identity/github-oidc | OIDC provider, GitHub Actions role, Terraform role | Auto   | Free                     |
| networking           | VPC, subnets, IGW, NAT Gateway, VPC endpoint       | Manual | NAT ~£1/day when enabled |
| compute              | EC2 validation instance, SSM access                | Auto   | Stop between sessions    |
| storage              | Application S3 bucket, lifecycle rules             | Auto   | ~£1/month                |
| ecr                  | Container registry, image scanning                 | Auto   | Free until images pushed |
| observability        | CloudWatch, CloudTrail, SNS alerts                 | Auto   | ~$2/month                |
| compute-scaling      | ALB, ASG, Launch Template, scaling policy          | Manual | ~$13/month when running  |
| secrets-manager      | Secrets Manager secrets, resource policies         | Auto   | ~$0.80/month             |
| eks                  | EKS cluster, node group, IRSA                      | Manual | ~$140/month when running |

---

## CI/CD Pipeline

### Authentication

Two-step OIDC role chaining — no stored credentials anywhere:

GitHub runner
→ OIDC token exchange → GitHub Actions role
→ sts:AssumeRole → Terraform provisioning role
→ provisions resources

### Module Registry

`ci_enabled: true` modules apply automatically on merge to main. `ci_enabled: false` modules are planned on PRs for visibility but require manual apply — either cost-sensitive or high blast radius.

| Module          | ci_enabled | Reason                             |
| --------------- | ---------- | ---------------------------------- |
| identity        | true       | Stable, low blast radius           |
| compute         | true       | Stable                             |
| storage         | true       | Stable                             |
| ecr             | true       | Stable                             |
| observability   | true       | Stable                             |
| secrets-manager | true       | Stable                             |
| networking      | false      | Cost-sensitive, NAT Gateway toggle |
| compute-scaling | false      | ALB costs ~$13/month               |
| eks             | false      | Cluster costs ~$140/month          |

---

## Deployment Order

Full deployment from a clean checkout. See `stratum-platform/docs/runbooks/phase1-aws-deploy.md` for the complete runbook with verification steps.

```bash
# 1. Bootstrap — local state, one-time
cd platform/bootstrap && terraform init && terraform apply

# 2. Identity — manual, requires elevated IAM
cd platform/identity/github-oidc && terraform init && terraform apply

# 3. Networking — manual, enable NAT when needed
cd platform/networking && terraform init && terraform apply

# 4-9. Remaining modules — CI applies automatically after merge
# Manual apply for compute-scaling and eks when needed
```

---

## Security Model

**No stored credentials** — GitHub Actions authenticates via OIDC. Terraform operates under an assumed IAM role. No access keys in GitHub secrets or environment variables.

**Least privilege** — the Terraform provisioning role has scoped permissions per service domain: state, IAM, EC2, ELB, ECR, observability, EKS. Each domain is a separate IAM policy document.

**Private compute** — all EC2 instances and EKS nodes deploy into private subnets. No direct internet ingress. SSM Session Manager provides shell access without SSH or open ports.

**Encryption at rest** — all S3 buckets, EBS volumes, and ECR repositories use AES256 encryption. All state files encrypted in S3.

**Audit trail** — CloudTrail captures every AWS API call to S3 and CloudWatch Logs. SNS alerts on billing threshold, CPU utilisation, and instance health.

---

## IRSA — Pod-Level AWS Identity

EKS pods authenticate to AWS via IAM Roles for Service Accounts. Each workload gets its own IAM role scoped to exactly what it needs.

Pod starts with service account annotation
→ EKS injects projected token volume
→ AWS SDK exchanges token for temporary credentials
→ Pod operates as scoped IAM role
→ No access keys, no node role inheritance

The stratum-service validation application demonstrates this pattern
— it retrieves a secret from Secrets Manager via IRSA with no credentials configured in the application code.

---

## Cost Management

This platform runs on a £10/month budget. Resources that carry significant hourly cost are destroyed between sessions.

| Resource     | Action                                    | Saving       |
| ------------ | ----------------------------------------- | ------------ |
| NAT Gateway  | Toggle via `nat_gateway_enabled` variable | ~£1/day      |
| EC2 instance | Stop via CLI between sessions             | ~$0.01/hour  |
| ALB + ASG    | Destroy via targeted apply                | ~$0.018/hour |
| EKS cluster  | Destroy when not in use                   | ~$0.19/hour  |

---

## Architecture Decision Records

| ADR     | Decision                          |
| ------- | --------------------------------- |
| ADR-001 | Phase 1 engineering retrospective |

---

## Related Repositories

| Repository                                                           | Purpose                   |
| -------------------------------------------------------------------- | ------------------------- |
| [azure-landing-zone](https://github.com/moshstaq/azure-landing-zone) | Azure platform foundation |
| [stratum-platform](https://github.com/moshstaq/stratum-platform)     | Multi-cloud consumer      |

---

## Author

Moshood Adisa — github.com/moshstaq
