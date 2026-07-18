# ADR-005: Phase 1 Engineering Retrospective

**Date:** July 2026
**Status:** Accepted
**Author:** Moshood Adisa
**Repository:** aws-landing-zone

## Context

Phase 1 of Project Stratum established the AWS landing zone foundation across nine modules: bootstrap, identity, networking, compute, storage, ECR, observability, compute-scaling, and secrets-manager. This ADR captures the significant engineering decisions and lessons learned during Phase 1 that inform the standards and patterns for subsequent phases.

## Decision 1 — Session-scoped cost management over persistent infrastructure

### Context

The programme budget is £10/month across both clouds. Several Phase 1 resources carry significant hourly costs: NAT Gateway (~$0.045/hour), ALB (~$0.018/hour), and EC2 instances (~$0.01/hour). Running these persistently would exhaust the budget within days.

### Decision

Resources are deployed for the duration of active working sessions and destroyed or stopped when not in use. This is implemented via three mechanisms:

- **Toggle variable**
  — `nat_gateway_enabled` in networking controls NAT Gateway provisioning. Default is `false`. Set to `true` in local `terraform.tfvars` when needed.
- **EC2 stop/start**
  — instance is stopped between sessions via AWS CLI. State and configuration are preserved.
- **Targeted destroy**
  — ALB and ASG are destroyed between sessions. Recreated via `terraform apply` when needed.

### Consequences

**Positive:**

- Phase 1 actual spend: ~$0.00 due to cost discipline and free tier coverage
- Engineers develop habit of treating infrastructure as ephemeral rather than permanent
- Cost management is encoded in configuration, not just in documentation

**Negative:**

- NAT Gateway toggle required refactoring after targeted destroy caused cascade destruction of dependent resources including private route table and VPC endpoint. Lesson: targeted destroy resolves dependencies — use CLI deletion for cost management, not targeted Terraform destroy.
- ALB and ASG must be recreated at the start of each session where compute scaling is needed, adding approximately 3 minutes to session setup time.

---

## Decision 2 — Explicit bucket policies required for cross-identity S3 access

### Context

Multiple CI pipeline failures occurred with `403 Forbidden` on `HeadBucket` despite the Terraform provisioning role having `s3:HeadBucket` in its IAM identity policy. The buckets were created by IAM user `mosh` and accessed by the Terraform assumed role — two distinct identities within the same account.

### Decision

Every S3 bucket in the platform requires an explicit `AllowTerraformRole` statement in its resource-based bucket policy granting the Terraform provisioning role access. IAM identity policy alone is insufficient when the requesting
identity differs from the bucket owner, even within the same AWS account.

This differs from Azure behaviour where a managed identity with the correct RBAC role assignment can access a storage
account regardless of which identity created it.

### Consequences

**Positive:**

- Bucket access is explicitly documented in code — no implicit permissions that depend on ownership relationships
- The dual-layer evaluation model (IAM policy + resource policy) is now understood and applied consistently across
  S3, ECR, and Secrets Manager

**Negative:**

- Every new S3 bucket requires an additional bucket policy resource. This is additional Terraform code per bucket but
  is the correct production pattern.
- The failure mode is a 403 that looks identical to an IAM permission gap, making diagnosis harder without understanding the ownership-based access evaluation.

---

## Decision 3 — CI pipeline matrix reflects blast radius, not just capability

### Context

The initial CI pipeline applied all modules automatically on merge to main. This caused two categories of problem: expensive resources being recreated on every merge, and sensitive infrastructure being modified without human review.

### Decision

The `terraform-modules.json` registry distinguishes between modules that are safe for automated apply and modules that require human gates:

- `ci_enabled: true` — identity, compute, storage, ECR, observability, secrets-manager. Stable, low blast radius,
  safe to auto-apply.
- `ci_enabled: false` — networking, compute-scaling. Cost-sensitive or high blast radius. CI plans for visibility,
  never auto-applies.

This mirrors the pattern established in azure-landing-zone where governance and github-oidc were designated manual-only due to management group scope requirements.

### Consequences

**Positive:**

- NAT Gateway and ALB are never recreated unexpectedly by CI
- Networking changes require deliberate human apply, preventing accidental destruction of the VPC foundation
- The registry is self-documenting — `ci_enabled: false` with a comment explains why each module is excluded

**Negative:**

- Manual modules require the engineer to remember to apply locally after merging. A merge without a subsequent local
  apply leaves the repository ahead of the deployed state. Mitigated by the runbook which documents this explicitly.

---

## References

- `docs/runbooks/phase1-aws-deploy.md` — deployment runbook
- `docs/programme/phase1-cost-reconciliation.md` — cost analysis
- `docs/programme/phase1-security-review.md` — security findings
- `.github/terraform-modules.json` — CI module registry
- ADR-003 — single NAT Gateway cost decision
