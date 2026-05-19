# ADR 0002: IaC Tool - Terraform

**Status:** Accepted

## Context
The assignment accepts Terraform, Pulumi, or gcloud/aws CLI scripts.

## Decision
Use Terraform with modular structure (`modules/network`, `modules/iam`, `modules/compute`, `modules/observability`).

## Consequences
**Positive:**
- Industry-standard; immediately readable by any DevOps reviewer
- GCS backend with versioning provides real state management (shared, locking, history)
- Module reuse: adding a second inference VM or a second region is a `count`/`for_each` change
- Integrates with the entire CI toolchain: tflint, tfsec, checkov, infracost

**Negative:**
- More initial boilerplate than gcloud scripts
- State backend requires the GCS bucket to exist before `terraform init` (mitigated by `scripts/bootstrap.sh`)

**vs Pulumi:**
Pulumi would be appropriate for teams already in a typed language. For an infrastructure-focused assignment reviewed by engineers unfamiliar with the specific language, Terraform's declarative HCL is more universally legible.
