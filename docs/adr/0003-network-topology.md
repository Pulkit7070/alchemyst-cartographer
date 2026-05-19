# ADR 0003: Network Topology - Public + Private Subnets + Cloud NAT

**Status:** Accepted

## Context
The assignment requires "workers in a private subnet" with "public internet access limited to the API gateway."

## Decision
Two-subnet topology:
- `public-subnet (10.10.1.0/24)`: gateway VM, has external IP
- `private-subnet (10.10.2.0/24)`: inference VM, no external IP
- Cloud NAT on private subnet for outbound-only internet (model downloads, pip install)

## Consequences
**Positive:**
- Inference VM is unreachable from the internet by design (no route in, only Cloud NAT out)
- Matches the assignment requirement precisely
- Defense in depth: even if the gateway VM is compromised, the inference VM has no inbound path from internet

**Negative:**
- Two subnets + router + NAT adds ~3 extra Terraform resources vs a single subnet
- Cloud NAT charges ~$0.045/hr (~$32/mo) - acceptable for production; acceptable for a $300 credit demo

**vs single subnet:** A single subnet with firewall rules technically works but proves no real understanding of network isolation. Private subnet with no external IP is the production-correct approach.
