# ADR 0001: Cloud Provider - GCP

**Status:** Accepted

## Context
The assignment permits AWS or GCP. Both support the required primitives (VPC, private subnets, NAT, compute VMs).

## Decision
Use GCP.

## Consequences
**Positive:**
- Production GCP experience at ArmorIQ means no ramp-up time
- GCP's IAP TCP forwarding eliminates the need for a bastion host entirely - SSH is IAM-gated with no public port 22
- Cloud NAT is simpler to configure than AWS NAT Gateway for single-region deployments
- $300 free credit covers the full assignment

**Negative:**
- Slightly less default documentation online compared to AWS
- Specific gcloud CLI commands differ from AWS equivalents in reviewer's mental model
