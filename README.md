# AWS Landing Zone

AWS platform foundation for Stratum Retail Group, built with Terraform.
This repository provisions the boundary the US estate runs on — VPC
networking, identity, storage, observability and secrets. It contains no
cluster and no application code: those belong to the platform and
workload layers above it. Every resource is defined in Terraform, every
deployment authenticates via OIDC with no stored credentials, and every
significant decision is recorded in an ADR.

[![Terraform](https://img.shields.io/badge/Terraform-1.5+-623CE4?logo=terraform)](https://terraform.io)
[![AWS](https://img.shields.io/badge/AWS-Landing%20Zone-FF9900?logo=amazon-aws)](https://aws.amazon.com)
[![CI/CD](https://img.shields.io/badge/CI%2FCD-GitHub%20Actions-2088FF?logo=github-actions)](https://github.com/features/actions)

---

## Business Context

Stratum Retail Group acquired a US-based retail business running on AWS.
Two problems came with it: unpredictable traffic spikes during flash
sales crashed the US website and lost revenue, and there was no
visibility into system errors or performance bottlenecks across either
estate.

This landing zone provides the foundation that addresses both — elastic
compute scaling, and the observability layer that surfaces failures
before they become incidents.

---

## Scope

This repository is a platform foundation. It provisions network
boundaries, identities and shared services. It does not contain:

| Not here                              | Where it lives                                                                        |
| ------------------------------------- | ------------------------------------------------------------------------------------- |
| EKS cluster, node group, IRSA role    | [stratum-platform](https://github.com/moshstaq/stratum-platform) `terraform/aws/eks/` |
| Application code and container images | [stratum-workloads](https://github.com/moshstaq/stratum-workloads)                    |
| Per-workload IAM, storage, registries | stratum-platform environment module                                                   |

This mirrors the Azure side, where `azure-landing-zone` provides the
boundary and `taskflow-platform` owns the AKS cluster and its workloads.
Consumers reach the landing zone through provider-native data sources —
no shared Terraform state.

---

## Architecture

### Network Topology

```
Internet
   │
   ▼
Application Load Balancer (public subnets)
   │
   ▼
Auto Scaling Group (private subnets)
   │
   ├── EKS worker nodes  (cluster owned by stratum-platform)
   └── EC2 validation instance
          │
          ▼
   NAT Gateway → Internet
   (outbound only, cost-toggled)
```

### VPC Design

```
vpc-platform (10.0.0.0/16)
├── snet-public-us-east-1a   (10.0.1.0/24)   ← ALB, NAT Gateway
├── snet-public-us-east-1b   (10.0.2.0/24)   ← ALB, multi-AZ
├── snet-private-us-east-1a  (10.0.10.0/24)  ← Compute, EKS nodes
└── snet-private-us-east-1b  (10.0.11.0/24)  ← Compute, EKS nodes
```

Subnet IDs are AWS-assigned and change when resources are recreated.
Reference subnets by CIDR or by data source, never by hardcoded ID.

### Terraform State

Each module owns an isolated state file in S3. No shared state.
Cross-module references use AWS data sources exclusively.

```
stratum-tfstate-7pbqp4 (S3)
├── platform-bootstrap.tfstate
├── platform-github-oidc.tfstate
├── platform-networking.tfstate
├── platform-compute.tfstate
├── platform-storage.tfstate
├── platform-ecr.tfstate
├── platform-observability.tfstate
├── platform-compute-scaling.tfstate
└── platform-secrets-manager.tfstate
```

---

## Repository Structure

```
aws-landing-zone/
├── .github/
│   ├── terraform-modules.json      ← module registry
│   └── workflows/
│       ├── terraform-plan.yml      ← PR: plan per module
│       └── terraform-apply.yml     ← merge: apply enabled modules
│
├── docs/
│   └── adr/
│       ├── ADR-001-phase1-retrospective.md
│       └── ADR-002-phase5-retrospective.md
│
└── platform/
    ├── bootstrap/                  ← tier 0: state backend
    ├── identity/
    │   └── github-oidc/            ← tier 1: OIDC, IAM roles
    ├── networking/                 ← tier 1: VPC, subnets, routing
    ├── compute/                    ← tier 2: EC2, SSM access
    ├── storage/                    ← tier 2: S3 application bucket
    ├── ecr/                        ← tier 2: container registry
    ├── observability/              ← tier 2: CloudWatch, CloudTrail, SNS
    ├── compute-scaling/            ← tier 3: ALB, ASG, launch template
    └── secrets-manager/            ← tier 3: Secrets Manager
```

---

## Platform Modules

| Module               | Purpose                                                                     | CI     | Cost                     |
| -------------------- | --------------------------------------------------------------------------- | ------ | ------------------------ |
| bootstrap            | S3 state backend, DynamoDB locking                                          | Manual | ~£1/month                |
| identity/github-oidc | OIDC provider, IAM roles for three repositories, EKS cluster and node roles | Auto   | Free                     |
| networking           | VPC, subnets, IGW, NAT Gateway, S3 VPC endpoint                             | Manual | NAT ~£1/day when enabled |
| compute              | EC2 validation instance, SSM access                                         | Auto   | Stop between sessions    |
| storage              | Application S3 bucket, lifecycle rules                                      | Auto   | ~£1/month                |
| ecr                  | Container registry, immutable tags, scan on push                            | Auto   | Free until images pushed |
| observability        | CloudWatch, CloudTrail, SNS, dashboard, alarms, Route53 health checks       | Auto   | ~$2/month                |
| compute-scaling      | ALB, ASG, launch template, target tracking policy                           | Manual | ~$13/month when running  |
| secrets-manager      | Secrets Manager secrets, resource policies                                  | Auto   | ~$0.80/month             |

### IAM centralisation

The identity module owns every IAM role in the estate, including the
EKS cluster role and node role. Those roles persist independently of
the cluster, which is destroyed between sessions for cost management —
so the role definitions survive teardown and a single module answers
"what permissions exist here".

The exceptions are the EKS OIDC provider and the IRSA pod role, which
live in stratum-platform because both derive from the cluster's issuer
URL and cannot exist without it. That split is deliberate and recorded
in ADR-002.

---

## Observability

The observability module provides platform telemetry for the AWS estate
and the workloads running on it.

**Logging and audit**

| Resource                  | Purpose                                    |
| ------------------------- | ------------------------------------------ |
| `/stratum/platform`       | CloudTrail API audit, also delivered to S3 |
| `/stratum/ec2`            | EC2 instance logs                          |
| `/stratum/application`    | Application logs                           |
| `stratum-platform-trail`  | CloudTrail, S3 and CloudWatch destinations |
| `stratum-platform-alerts` | SNS topic, email delivery                  |

**Dashboard** — `stratum-platform` in CloudWatch. Seven widgets: pod CPU
and memory per service, pod restart count, node CPU and memory, and
running pod count. Metrics arrive via the Container Insights EKS addon,
which runs a CloudWatch agent and Fluent Bit on every node.

**Alarms**

| Alarm                       | Threshold  | Evaluation     |
| --------------------------- | ---------- | -------------- |
| stratum-pod-cpu-warning     | > 70%      | 2 periods      |
| stratum-pod-cpu-critical    | > 90%      | 1 period       |
| stratum-pod-memory-warning  | > 70%      | 2 periods      |
| stratum-pod-memory-critical | > 90%      | 1 period       |
| stratum-pod-restart         | > 0        | 1 period       |
| stratum-pod-count-low       | < 4        | 2 periods      |
| stratum-ec2-cpu-high        | EC2 CPU    | infrastructure |
| stratum-ec2-status-check    | EC2 health | infrastructure |
| stratum-estimated-charges   | billing    | infrastructure |

Warning alarms require two consecutive breaches to avoid firing on
transient spikes. Critical alarms fire immediately.

**Health checks** — four Route53 CloudWatch-metric health checks
monitoring the critical alarms, aggregated by a calculated health check
with a child threshold of four. A CloudWatch alarm on the aggregate
gives one platform-level health signal. Route53 is used as a health
aggregator rather than an HTTP prober because the account cannot create
load balancers through the Kubernetes cloud controller.

**Known coupling.** The pod alarms and dashboard reference
`ClusterName = eks-platform` and `Namespace = stratum-workloads`, both
owned by other repositories. Renaming either breaks the alarms silently —
the metric dimension stops matching and the alarm reports insufficient
data rather than failing. Accepted and recorded in ADR-002; revisit in
Phase 6 alongside cross-cloud visibility, which this layer does not
provide.

---

## CI/CD Pipeline

### Authentication

Two-step OIDC role chaining. No stored credentials anywhere.

```
GitHub runner
  → OIDC token exchange → GitHub Actions role
    → sts:AssumeRole     → Terraform provisioning role
      → provisions resources
```

### Module Registry

`ci_enabled: true` applies automatically on merge to main.
`ci_enabled: false` plans on PRs for visibility but requires a manual
apply — either cost-sensitive or high blast radius.

| Module          | ci_enabled | Reason                             |
| --------------- | ---------- | ---------------------------------- |
| identity        | true       | Stable, low blast radius           |
| compute         | true       | Stable                             |
| storage         | true       | Stable                             |
| ecr             | true       | Stable                             |
| observability   | true       | Stable                             |
| secrets-manager | true       | Stable                             |
| networking      | false      | Cost-sensitive, NAT Gateway toggle |
| compute-scaling | false      | ALB ~$13/month                     |

Manual modules carry a known risk: a merge without a subsequent local
apply leaves the repository ahead of deployed state. Weekly drift
detection covers `ci_enabled: true` modules only, which is the wrong
way round — extending it to manual modules is Phase 6 work.

---

## Deployment Order

Full deployment from a clean checkout. Complete runbook with
verification steps: `stratum-platform/docs/runbooks/phase1-aws-deploy.md`

```bash
# 1. Bootstrap — local state, one-time
cd platform/bootstrap && terraform init && terraform apply

# 2. Identity — manual, requires elevated IAM
cd platform/identity/github-oidc && terraform init && terraform apply

# 3. Networking — manual, enable NAT when needed
cd platform/networking && terraform init && terraform apply

# 4-9. Remaining modules — CI applies on merge
#      Manual apply for compute-scaling when needed
```

---

## Security Model

**No stored credentials** — GitHub Actions authenticates via OIDC,
Terraform operates under an assumed role. No access keys in GitHub
secrets or environment variables.

**Least privilege** — the Terraform provisioning role has scoped
permissions per service domain: state, IAM, EC2, ELB, ECR,
observability, EKS, secrets, Route53. Each domain is a separate IAM
policy document. Consumer repositories have their own role pairs with
read-only access to platform resources.

**Private compute** — EC2 instances and EKS nodes deploy into private
subnets. No direct internet ingress. SSM Session Manager provides shell
access without SSH or open ports.

**Encryption at rest** — S3 buckets, EBS volumes and ECR repositories
use AES256. State files encrypted in S3.

**Audit trail** — CloudTrail captures every API call to S3 and
CloudWatch Logs.

**Known operational risk.** Resources are frequently built locally under
`AdministratorAccess` and only later exercised by the scoped CI role.
Three permission gaps have been found this way — ECR write, data source
reads, and Route53. Assuming the provisioning role locally before
committing surfaces them at build time instead. See ADR-002.

---

## IRSA — Pod-Level AWS Identity

EKS pods authenticate to AWS via IAM Roles for Service Accounts. Each
workload gets its own IAM role scoped to what it needs, rather than
inheriting the node role.

```
Pod starts with service account annotation
  → EKS injects a projected token volume
    → AWS SDK exchanges the token for temporary credentials
      → pod operates as a scoped IAM role
```

No access keys, no node role inheritance, no credentials in application
code, container images or Kubernetes manifests.

The trust policy is the contract between platform and workload teams:
the platform provides the mechanism, the workload declares which service
accounts may assume the role. It is defined in stratum-platform
alongside the cluster, and must be updated when a workload is onboarded.

---

## Cost Management

£10/month budget across both clouds. Resources carrying significant
hourly cost are destroyed between working sessions.

| Resource     | Action                            | Rate         |
| ------------ | --------------------------------- | ------------ |
| NAT Gateway  | Toggle via `nat_gateway_enabled`  | ~$0.045/hour |
| EC2 instance | Stop via CLI between sessions     | ~$0.01/hour  |
| ALB + ASG    | Targeted destroy between sessions | ~$0.018/hour |

Actual spend across the programme to date is under one cent. EKS cost is
carried by stratum-platform, which owns the cluster.

---

## Architecture Decision Records

| ADR                                                 | Decision                                                                                                                                 |
| --------------------------------------------------- | ---------------------------------------------------------------------------------------------------------------------------------------- |
| [ADR-001](docs/adr/ADR-001-phase1-retrospective.md) | Phase 1 retrospective — session-scoped cost management, S3 cross-identity bucket policies, CI blast-radius classification                |
| [ADR-002](docs/adr/ADR-002-phase5-retrospective.md) | Phase 5 retrospective — observability ownership, ContainerInsights dimensions, Route53 as health aggregator, configuration-loss incident |

---

## Related Repositories

| Repository                                                           | Relationship                                                                        |
| -------------------------------------------------------------------- | ----------------------------------------------------------------------------------- |
| [stratum-platform](https://github.com/moshstaq/stratum-platform)     | Multi-cloud IDP. Consumes this foundation via data sources and owns the EKS cluster |
| [stratum-workloads](https://github.com/moshstaq/stratum-workloads)   | FastAPI services deployed through the Golden Path                                   |
| [azure-landing-zone](https://github.com/moshstaq/azure-landing-zone) | Azure platform foundation — UK estate                                               |

---

## Author

Moshood Adisa — [github.com/moshstaq](https://github.com/moshstaq)
