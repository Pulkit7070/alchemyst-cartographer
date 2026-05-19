# ADR 0006: Process Management - systemd (Not Docker/k8s)

**Status:** Accepted

## Context
Three services need to run reliably on two VMs: iii-engine, caller-worker, inference-worker.

Options: systemd units, Docker Compose, Kubernetes.

## Decision
Use systemd units directly on the VMs.

## Consequences
**Positive:**
- Zero runtime overhead - no container daemon, no orchestration layer
- systemd is always present on Ubuntu 22.04 LTS; no extra installs
- `Restart=always` + `RestartSec` provides automatic recovery equivalent to Docker's `restart: always`
- `After=` + `Requires=` models the service dependency (caller-worker waits for engine)
- Hardening options (`NoNewPrivileges`, `ProtectSystem`, `PrivateTmp`) are native systemd features - equivalent to Docker's `--security-opt` but simpler to configure
- Logs go to journald → Cloud Logging without extra configuration

**Negative:**
- Not portable: systemd units are tied to the VM OS. Docker would be more portable.
- Updating the app requires SSH + restart, not `docker pull`. Mitigated by `make deploy` re-running the startup script on Terraform apply.

**When to migrate:**
When the team wants to swap inference runtimes frequently (e.g., A/B testing vLLM vs TRT-LLM), Docker Compose on the inference VM makes sense. When concurrency needs grow beyond 2 VMs, migrate to GKE + Triton as described in `docs/SCALING.md`.
