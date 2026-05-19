# Security

## Threat Model (STRIDE)

| Threat | Vector | Control |
|--------|--------|---------|
| **Spoofing** | Impersonate VM identity | Per-VM service accounts; OS Login requires Google identity |
| **Tampering** | Modify app in transit | App bundle served from GCS over TLS; Shielded VM integrity monitoring |
| **Repudiation** | Deny API calls | Cloud Audit Logs (Admin + Data Access) on all project resources |
| **Info Disclosure** | Exfiltrate model weights or state | Inference VM has no public IP; secrets in Secret Manager (not env files) |
| **Denial of Service** | Flood public API | Cloud Armor rate limiting (100 req/min/IP) |
| **Elevation of Privilege** | Escape service user | systemd `NoNewPrivileges=true`; `ProtectSystem=strict`; `PrivateTmp` |

---

## Hardening Checklist

### Network
- [x] Inference VM has no external IP (verified by `scripts/verify-isolation.sh`)
- [x] Deny-all default firewall (no `default-allow-*` rules)
- [x] iii engine port 49134 only reachable from private subnet CIDR
- [x] SSH only via IAP (source `35.235.240.0/20`) - not from open internet
- [x] Cloud NAT for private subnet egress (no public IP needed for `pip install`)
- [x] VPC Flow Logs enabled on both subnets (5s aggregation, 50% sampling)
- [ ] VPC Service Controls (todo: production hardening for data exfil prevention)

### Compute
- [x] Shielded VMs: Secure Boot + vTPM + Integrity Monitoring
- [x] OS Login enabled project-wide (IAM-gated SSH, audit-logged)
- [x] Per-VM service accounts (not the default compute SA with broad permissions)
- [x] Least-privilege IAM: `logging.logWriter`, `monitoring.metricWriter`, `storage.objectViewer` only
- [ ] CMEK disk encryption (using Google-managed keys currently; upgrade path: Cloud KMS CMEK)

### Application
- [x] systemd hardening: `NoNewPrivileges`, `ProtectSystem=strict`, `PrivateTmp`, `ProtectHome`
- [x] Services run as unprivileged `alchemyst` user (not root)
- [x] `TimeoutStartSec=300` prevents zombie services if model load hangs
- [ ] API authentication (no auth currently - acceptable for assignment; production: API key via Secret Manager header check in caller-worker)
- [ ] TLS termination (documented in scaling path; requires a domain)

### IAM
- [x] Owner email explicitly bound to IAP tunnel accessor + OS Admin Login
- [x] No project-level `owner` or `editor` granted to service accounts
- [ ] Workload Identity Federation for CI/CD (replaces service account key files)

### Audit & Observability
- [x] Cloud Audit Logs (Admin Activity + Data Access) - enabled by default on GCP
- [x] VPC Flow Logs → Cloud Logging
- [x] Cloud Monitoring alerts: API down, CPU spike

---

## Verified Controls

Run `make isolation` to re-verify isolation properties any time:
- inference-vm has no external IP
- port 49134 (iii engine) is blocked from internet
- port 3111 (API) is reachable
- port 22 is blocked from direct internet (IAP only)
