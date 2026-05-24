# Scaling to 100x

This document covers what changes - and what stays the same - when scaling
the current single-VM deployment to production-grade distributed inference.

---

## Defining 100x

"100x" is ambiguous. Three concrete interpretations:

| Axis | Today | 100x |
|------|-------|------|
| Model size | 270M params, Q8 GGUF, 241 MB | ~27B params (Gemma 27B / Llama 3 70B Q4) |
| Throughput | ~2-5 req/s sustained, CPU | 200-500 req/s sustained |
| Latency | 500ms-3s p50 (CPU) | <200ms TTFT on GPU |

Each axis requires a different set of changes. Below we walk through all three.

---

## Axis 1 - 100x Bigger Model

### The compute problem
Gemma 3 270M Q8 sits in 241 MB of RAM and runs acceptably on CPUs.
A 27B parameter model in Q4 quantization needs ~14 GB of VRAM - beyond any CPU.

| Model | Quant | VRAM needed | Target GPU |
|-------|-------|-------------|------------|
| Gemma 3 1B | Q8 | ~1 GB | CPU or T4 |
| Gemma 3 4B | Q4 | ~2.5 GB | T4 (16 GB) |
| Gemma 3 12B | Q4 | ~7 GB | T4 or L4 |
| Gemma 3 27B | Q4 | ~14 GB | L4 (24 GB) or A100 40 GB |
| Llama 3 70B | Q4 | ~40 GB | A100 80 GB or 2× L4 |

### What changes in the infra
1. Replace `e2-standard-4` with `a2-highgpu-1g` (A100 40 GB) or `g2-standard-4` (L4 24 GB).
2. Switch runtime from `transformers` to **vLLM** or **TensorRT-LLM**:
   - **vLLM**: drop-in, OpenAI-compatible API, PagedAttention eliminates KV cache fragmentation, continuous batching out of the box. Best for getting started on GPU quickly.
   - **TensorRT-LLM**: NVIDIA-compiled kernels for the specific GPU. 20-40% higher throughput vs vLLM after compilation. Worth it when the model is fixed and throughput matters.
3. The iii `inference-worker` becomes a thin wrapper that calls vLLM's local HTTP server instead of running transformers inline.

### Quantization tradeoffs
| Format | Size reduction | Quality loss | When to use |
|--------|---------------|--------------|-------------|
| FP16 | baseline | none | evaluation, fine-tuning |
| BF16 | same as FP16 | none on modern GPUs | A100/H100 training |
| Q8 | 50% | <1% | safe default for most deployments |
| Q4_K_M | 75% | ~2-3% | when VRAM is the bottleneck |
| Q2 | 85% | significant | edge/IoT only |

---

## Axis 2 - 100x Throughput

### Continuous batching (the biggest win)
The current `transformers.pipeline()` processes one request at a time.
vLLM's **PagedAttention + continuous batching** dynamically groups requests
mid-generation, keeping the GPU ~80% utilized vs ~5% with naive batching.
This alone delivers 10-30× throughput improvement.

### Horizontal scaling via Managed Instance Groups
```
External HTTPS LB
        │
   Backend Service (HTTP/2)
        │
   ┌────┴────┐
   │   MIG   │  ← Autoscaled on custom metric: inference_requests_pending
   │  N VMs  │    Min: 1, Max: 10, cooldown: 5 min
   └─────────┘
Each VM: vLLM serving gemma-3-27b on L4 GPU
```

Replace the single `inference-vm` with a GCP **Managed Instance Group** behind
an **Internal HTTP Load Balancer**. The autoscaler watches
`inference_requests_pending` (a custom metric pushed from the caller-worker)
and adds/removes inference VMs to keep queue depth below 5.

### At extreme scale: GKE + Triton + Dynamo
When sustained load exceeds ~100 req/s or you need multi-model routing:

1. **GKE Autopilot** with NVIDIA GPU node pools (T4/L4 nodes auto-provisioned).
2. **NVIDIA Triton Inference Server** as the serving frontend: wraps vLLM or TensorRT-LLM backends, exposes gRPC + HTTP, dynamic batching, multi-model, Prometheus metrics.
3. **NVIDIA Dynamo** (2025+) for disaggregated prefill/decode: routes compute-heavy prefill to dedicated nodes and memory-bound decode to separate decode nodes. Scales prefill and decode independently - critical when batch sizes are large.

### What stays the same
The iii framework's worker abstraction is the correct architectural decision here.
To move from `transformers` → vLLM → Triton, you only change the
`inference-worker` implementation. The caller-worker, the RPC contract
(`inference::run_inference`), the HTTP surface, the network topology, and all
Terraform modules stay unchanged. This is the value of the worker-per-concern design.

---

## Axis 3 - Latency at Scale

### Key metrics to track (not just request latency)
- **TTFT (Time To First Token)**: latency until the user sees the first word. Dominates perceived responsiveness.
- **TPOT (Time Per Output Token)**: throughput once generation starts. Drives p99 for long responses.
- **Queue depth**: how many requests are waiting for a GPU slot.

### Techniques
| Technique | Win | Complexity |
|-----------|-----|-----------|
| Continuous batching (vLLM default) | 10-30× throughput | Low - automatic |
| Speculative decoding | ~2× TTFT reduction | Medium - need a draft model |
| KV cache offload (CPU/disk) | Enables longer context | Medium |
| Flash Attention 2 | ~2× attention speed | Low - pip install |
| Multi-GPU tensor parallelism | Linear throughput scaling | High - need NVLink |

### Speculative decoding in practice
Use a small draft model (e.g. Gemma 3 1B) to predict the next N tokens,
then verify in parallel with the large model. For typical chat prompts,
~60-70% of speculated tokens are accepted, cutting TTFT roughly in half
with no quality loss.

---

## Infrastructure evolution path

```
Stage 0 (this assignment)
  Single gateway VM + single inference VM
  CPU inference, 5 req/s, ~270M model

Stage 1 (next 3 months)
  Swap inference VM to L4 GPU
  Install vLLM, serve 12B model
  20-50 req/s, <500ms TTFT

Stage 2 (production)
  Managed Instance Group for inference
  Internal LB, autoscaling
  100+ req/s, multi-model routing

Stage 3 (at scale)
  GKE + Triton + Dynamo
  Disaggregated prefill/decode
  Multi-region, 1000+ req/s
```

Each stage requires changing only the inference tier. The gateway, networking,
IAM, and observability modules in this Terraform setup survive unchanged to Stage 2.
Stage 3 adds GKE modules alongside.
