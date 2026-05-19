# ADR 0004: SSH Access - IAP TCP Forwarding (No Bastion, No Public Port 22)

**Status:** Accepted

## Context
Operators need to SSH into both VMs for debugging. Options:
1. Open port 22 to the internet (0.0.0.0/0)
2. Bastion host in the public subnet
3. GCP Identity-Aware Proxy (IAP) TCP forwarding

## Decision
Use GCP IAP TCP forwarding. Firewall allows port 22 only from `35.235.240.0/20` (Google IAP CIDR).

## Consequences
**Positive:**
- No public port 22 exposure - eliminates brute-force SSH attack surface entirely
- Works for inference VM (private subnet, no public IP) - IAP tunnels through Google's network
- SSH access is IAM-gated: only identities with `roles/iap.tunnelResourceAccessor` can connect
- Every SSH session is Cloud Audit Logged automatically
- Eliminates a bastion VM ($13/mo e2-micro + management overhead)

**Negative:**
- Requires `gcloud` CLI; not a raw `ssh` command
- Slightly higher latency through the IAP tunnel (~20ms extra)
- If IAP service is degraded, SSH access is degraded (extremely rare; GCP SLA covers it)

**Command:**
```bash
gcloud compute ssh gateway-vm --tunnel-through-iap --zone=asia-south1-a
```
