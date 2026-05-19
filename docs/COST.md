# Cost Estimate

Monthly cost for the assignment deployment in `asia-south1` (Mumbai).

## Resource Breakdown

| Resource | Spec | Unit Cost | Monthly Est. |
|----------|------|-----------|--------------|
| gateway-vm | e2-small (2 vCPU, 2 GB), 30 GB pd-balanced | $0.0170/hr | ~$13 |
| inference-vm | e2-standard-4 (4 vCPU, 16 GB), 50 GB pd-balanced | $0.1340/hr | ~$98 |
| pd-balanced disks | 80 GB total | $0.054/GB/mo | ~$4 |
| Cloud Router | flat fee | $0.049/hr | ~$36 |
| Cloud NAT | ~10 GB egress (model download + traffic) | $0.045/GB | ~$5 |
| GCS buckets | state + bundles, ~500 MB | $0.020/GB/mo | ~$1 |
| VPC Flow Logs | 50% sampling, ~2 GB/mo | $0.50/GB | ~$1 |
| Cloud Monitoring | within free tier | - | $0 |
| **Total** | | | **~$158/mo** |

## Free Trial Coverage

GCP $300 free credit covers this deployment for **~60 days** at full 24/7 uptime.

## Cost Optimization Options

| Optimization | Monthly Saving | Tradeoff |
|-------------|---------------|----------|
| Preemptible inference VM | ~$74 (75% discount) | Up to 24hr interruptions; fine for batch, risky for live API |
| Scale to zero (stop VMs when idle) | ~$130 | Cold start penalty (~5 min for model reload) |
| Shared-core inference VM (e2-medium) | ~$70 | Higher latency on gemma-3-270m; may OOM on large prompts |
| Remove Cloud Router (use Cloud NAT-less setup) | ~$36 | Inference VM loses internet egress; model must be baked into image |

For the assignment (demo workload), stopping VMs between sessions is the most practical approach.

## Benchmark Results

_To be filled after running `make load`_

| Metric | Value |
|--------|-------|
| p50 latency | TBD |
| p95 latency | TBD |
| p99 latency | TBD |
| Sustained req/s | TBD |
| VM CPU during inference | TBD |

## GPU Upgrade Cost (for scaling reference)

| GPU VM | GPU | VRAM | Cost/mo | Max model size |
|--------|-----|------|---------|---------------|
| g2-standard-4 | L4 (1×) | 24 GB | ~$700 | 13B Q4 |
| a2-highgpu-1g | A100 40 GB (1×) | 40 GB | ~$2,200 | 27B Q4 |
| a2-highgpu-4g | A100 40 GB (4×) | 160 GB | ~$8,800 | 70B FP16 |
