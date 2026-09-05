# ADR-002: Phase 5 Engineering Retrospective

**Date:** September 2026
**Status:** Accepted
**Author:** Moshood Adisa
**Repository:** aws-landing-zone

## Context

Phase 5 of Project Stratum delivered resilience and observability for the AWS estate: CloudWatch Container Insights, a seven-widget platform dashboard, six workload alarms, Route53 health checks with
a calculated aggregate, a six-scenario DR runbook, and the first chaos test.

The phase also surfaced a configuration-loss incident that was not caused by Phase 5 work and would not have been found without it. This ADR records three decisions and one incident.

## Decision 1 — Workload observability remains in the landing zone

### Context

The CloudWatch dashboard, the six pod-level alarms, and the Route53
health checks reference `ClusterName = eks-platform` and
`Namespace = stratum-workloads`. Following the EKS extraction, the
cluster lives in stratum-platform and the workloads live in
stratum-workloads. A landing zone module therefore holds metric
dimensions that point at resources owned by two other repositories.

An alternative was available: move the workload-facing observability
into stratum-platform, alongside the cross-cloud data contracts that
already read from both clouds.

### Decision

Workload observability remains in `aws-landing-zone/platform/observability`.
The landing zone owns telemetry for its own estate, including
telemetry about workloads running on it.

### Consequences

**Positive:**

- One location for all AWS observability. An engineer responding to
  an incident does not have to determine which repository owns which
  alarm.
- The dashboard remains a single coherent view rather than being
  split across repositories by resource ownership.

**Negative:**

- The alarms are coupled to identifiers owned elsewhere. Renaming the
  `stratum-workloads` namespace or the `eks-platform` cluster breaks
  every pod-level alarm silently — the metric dimension simply stops
  matching and the alarm reports insufficient data rather than
  failing loudly.
- This is a known and accepted issue. Revisit in Phase 6 alongside
  the cross-cloud observability question, which is unresolved: the
  programme's stated problem is visibility across two estates, and
  the current implementation can only see AWS.

---

## Decision 2 — ContainerInsights metrics require three dimensions

### Context

The initial dashboard specified pod metrics with two dimensions,
`PodName` and `Namespace`. Every pod widget rendered empty while
node-level widgets returned data correctly.

### Decision

Pod-level ContainerInsights metrics are specified with three
dimensions: `PodName`, `ClusterName`, and `Namespace`. The dimension
set is verified against `aws cloudwatch list-metrics` before a
widget is written, rather than assumed from documentation.

### Consequences

**Positive:**

- The failure mode is now understood: an incomplete dimension set
  produces no error, no warning, and an empty graph. CloudWatch does
  not report a mismatch, it simply matches nothing.
- Verifying dimensions against `list-metrics` is now the first step
  when adding any widget or alarm.

**Negative:**

- The same class of silent failure applies to any alarm built on
  ContainerInsights. An alarm with a wrong dimension set sits in
  `INSUFFICIENT_DATA` indefinitely and looks healthy at a glance.

---

## Decision 3 — Route53 health checks over CloudWatch alarms

### Context

Route53 health checks were specified against the ALB endpoint.
The account could not create load balancers via the Kubernetes cloud
controller — `OperationNotPermitted: This AWS account currently does
not support creating load balancers` — so no public endpoint was
available for HTTP-based checking.

### Decision

Route53 health checks use `CLOUDWATCH_METRIC` type, monitoring the
four critical CloudWatch alarms directly. A `CALCULATED` health check
aggregates all four with a child threshold of 4, and a single
CloudWatch alarm on the aggregate provides one platform-level
health signal.

### Consequences

**Positive:**

- No public endpoint and no ALB cost. Detection capability is
  equivalent — failure surfaces automatically without a human
  watching a dashboard.
- Demonstrates Route53 as a health aggregator rather than only as an
  HTTP prober, which is the less commonly understood of its two
  health check modes.

**Negative:**

- Calculated health check status cannot be read via CLI —
  `GetHealthCheckStatus` rejects them and directs to the console or
  CloudWatch. Operational verification goes through the aggregate
  CloudWatch alarm instead. This is documented in the DR runbook.
- The check is one layer removed from the customer. An HTTP check
  against the ALB would detect an endpoint that is unreachable for
  reasons the pod metrics do not capture — DNS failure, listener
  misconfiguration, security group change.

---

## Incident — Configuration loss via stranded branch

### What happened

During the EKS extraction, `terraform plan` on
`platform/identity/github-oidc` proposed removing thirteen ECR write
permissions from the stratum-platform Terraform role, and the moved
EKS module carried an IRSA trust policy scoped to a single service
account rather than the three configured in Phase 4.

Both were Phase 4 fixes. Both were absent from `main`.

### Root cause

The fixes were committed to `feat/stratum-platform-aws-identity`
after that branch's pull request had already merged. Commits landing
on a branch whose PR is closed are not picked up by any subsequent
merge. They existed on the branch, locally and on the remote, and
nowhere else in the mainline.

The consequence differed for each fix:

- The ECR permissions were attached to a role in the identity module,
  which was never destroyed. The live policy retained them and they
  were recoverable via `aws iam get-role-policy`.
- The IRSA trust policy was attached to `role-eks-app-stratum`, which
  lived inside `platform/eks`. Session-scoped teardown of that module
  destroyed the role, and with it the only copy of the corrected
  trust policy. `aws iam get-role` returned `NoSuchEntity`.

### Detection

The regression was not found by review. It was found because the EKS
extraction forced a `terraform plan` against modules that had not
been planned since Phase 4. The plan proposed removing permissions
that had never been in the committed code.

`git log --oneline --graph --all` located the stranded branch. Without
`--all` the branch would not have appeared, and both fixes would have
been rebuilt from memory on the assumption they had never been
committed — leaving a live branch containing stale IAM for a future
merge to reintroduce.

### Contributing factors

**Applied from a branch that was already merged.** The PR workflow
implies that merging closes the work. Commits added afterwards have
no path into `main` without a new PR.

**No verification that live infrastructure matched committed code.**
Drift detection exists and runs weekly, but only covers
`ci_enabled: true` modules. The identity and EKS modules are
manual-apply and were outside its scope.

**Ephemeral resources holding non-ephemeral configuration.** The IRSA
role was treated as session-scoped because it lived in the EKS
module. Its trust policy was not session-scoped — it encoded which
workloads may assume the role, which is durable configuration.

### Remediation

- ECR permissions recovered from the live IAM policy and restored to
  the correct statement in `WorkloadEnvironmentProvisioning`.
- IRSA trust policy reconstructed in the new module location and
  verified against the service account manifests in
  `stratum-workloads/k8s/`, which are version-controlled and
  authoritative for namespace and service account names.
- `terraform plan` returning zero changes used as the acceptance
  test, on the basis that grep proves a string is present in a file
  while a plan proves the file matches what is deployed.
- The stranded branch deleted locally and on the remote after both
  fixes were confirmed present in `main`.

### Standards changes

**No `terraform apply` from uncommitted code.** To be added to
CONTRIBUTING.md. "Managed by Terraform" and "committed to version
control" are separate claims, and only the second survives a
resource teardown.

**Plan through the CI role, not the local admin identity.** Three
permission gaps have now been found the same way — ECR write in
Phase 4, four data source reads in Phase 3, Route53 in Phase 5. Each
followed the same pattern: a resource built locally under
`AdministratorAccess`, working correctly, failing in CI later on a
missing action. Assuming the provisioning role locally before
committing surfaces these at build time.

**Extend drift detection to manual-apply modules.** Weekly drift
detection covers only `ci_enabled: true`. The modules that most need
it are the ones excluded from automated apply, because they are the
ones where local changes are most likely to diverge from the
repository.

---

## References

- `platform/observability/main.tf` — CloudWatch dashboard
- `platform/observability/alarms-eks.tf` — six workload alarms
- `platform/observability/dns-route53.tf` — Route53 health checks
- `platform/identity/github-oidc/main.tf` — restored ECR permissions
- `stratum-platform/terraform/aws/eks/` — EKS module, new location
- `stratum-platform/docs/runbooks/dr-runbook.md` — six DR scenarios
- `stratum-platform/docs/programme/phase5-observability-gap-analysis.md`
  — requires correction, see Phase 5 outstanding work
