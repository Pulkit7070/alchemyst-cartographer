# alchemyst-cartographer

Gemma 3 270M on GCP, split across two VMs: a public gateway VM running the [iii](https://iii.dev) engine and a private inference VM with no public IP. Provisioned with Terraform, deployed via a single make command.

[![CI](https://github.com/Pulkit7070/alchemyst-cartographer/actions/workflows/terraform-ci.yml/badge.svg)](https://github.com/Pulkit7070/alchemyst-cartographer/actions)

## Architecture

```
                Internet
                    |
       PUBLIC SUBNET (10.10.1.0/24)
       +----------------------------+
       |  gateway-vm (e2-small)     |
       |  |- iii-engine  :49134     |
       |  +- caller-worker  :3111   |  <- HTTP API
       +----------+-----------------+
                  | VPC-internal WebSocket
       PRIVATE SUBNET (10.10.2.0/24)
       +----------------------------+
       |  inference-vm (e2-std-4)   |  no public IP
       |  +- inference-worker       |
       |     +- gemma-3-270m Q8     |
       +----------------------------+
              | Cloud NAT (egress only)
```

Request path: `POST /v1/chat/completions` -> caller-worker -> iii RPC -> inference-worker -> Gemma -> response

SSH access via IAP TCP forwarding only. Port 22 is not open on any VM.

## Deploy

```bash
# Prerequisites: gcloud CLI, terraform >= 1.9, gsutil
gcloud auth application-default login

# Create state bucket + enable APIs (run once)
bash scripts/bootstrap.sh <PROJECT_ID>

# Copy and fill in your variables
cp terraform/terraform.tfvars.example terraform/terraform.tfvars

# Init and deploy
cd terraform
terraform init -backend-config="bucket=<PROJECT_ID>-tf-state" -backend-config="prefix=cloud-cartographer"
cd ..
make deploy PROJECT_ID=<PROJECT_ID>
```

Takes about 8 minutes. Terraform output prints a working curl command when done.

## Try it

```bash
curl -X POST http://<GATEWAY_IP>:3111/v1/chat/completions \
  -H "Content-Type: application/json" \
  -d '{"messages":[{"role":"user","content":"What is the capital of France?"}]}'
```

Response is OpenAI-compatible so LangChain / OpenAI SDK clients work against it as-is.

## Live demo on GCP (e2-standard-4, asia-south1)

Deployed a single VM to GCP (`conmap-auto` project, `asia-south1-a`) to verify the stack runs end-to-end on a real instance. Health check and chat completions both passed:

```
$ curl -s http://8.231.122.148:3111/healthz
{"status":"ok","model":"gemma-3-270m"}

$ curl -s -X POST http://8.231.122.148:3111/v1/chat/completions \
    -H "Content-Type: application/json" \
    -d '{"messages":[{"role":"user","content":"What is 2+2?"}]}'
{
  "id": "chatcmpl-1779650862970",
  "object": "chat.completion",
  "created": 1779650862,
  "model": "gemma-3-270m",
  "choices": [
    {
      "index": 0,
      "message": {
        "role": "assistant",
        "content": "Whose name is 2+2?\nWhose name is 2+2?\nWhose name is 2+2?\nWhose"
      },
      "finish_reason": "stop"
    }
  ]
}
```

The model response is repetitive because Gemma 3 270M is a tiny model running on CPU with `MAX_NEW_TOKENS=32`. The API shape is fully OpenAI-compatible. VM was deleted after the test (~10 min runtime, ~$0.05).

## Test commands

```bash
make smoke                      # end-to-end API test with retry
make isolation                  # check inference VM is unreachable from internet
make chaos                      # kill the worker, confirm systemd brings it back
make load                       # k6 load test (needs k6 installed)
make destroy PROJECT_ID=x CONFIRM=yes
```

## Layout

```
terraform/
  modules/
    network/        VPC, subnets, Cloud NAT, firewall rules
    iam/            service accounts, OS Login, IAP bindings
    compute/        gateway + inference VMs, startup scripts, Shielded VM
    observability/  alerts, uptime check, dashboard
  main.tf / variables.tf / outputs.tf
systemd/            service units for iii-engine, caller-worker, inference-worker
quickstart/         iii application code
scripts/            bootstrap, bundle, deploy, smoke, chaos, load test
docs/
  SCALING.md        path from this to 500+ req/s with vLLM / TensorRT-LLM
  SECURITY.md       threat model, hardening notes
  RUNBOOK.md        how to SSH, check logs, redeploy, roll back
  adr/              6 architecture decision records
.github/workflows/  CI: fmt, validate, tflint, tfsec, checkov, infracost
```

## What was changed from the original quickstart

The `caller-worker/src/worker.ts` in the hiring repo has the HTTP trigger handler commented out. Uncommenting it and making the response shape OpenAI-compatible (adding `id`, `object`, `created`, `model`, `choices`) was the main code change. The `config.yaml` HTTP binding was also changed from `127.0.0.1` to `0.0.0.0` so the gateway VM accepts external requests.

## Cost estimate

| Resource | Spec | $/mo |
|---|---|---|
| gateway-vm | e2-small, asia-south1 | ~$13 |
| inference-vm | e2-standard-4, asia-south1 | ~$98 |
| Cloud NAT + Router | egress + flat fee | ~$39 |
| GCS + Flow Logs | minor | ~$3 |
| **Total** | | **~$153** |

Fits in GCP's $300 free trial for about 60 days.

## Scaling

See [docs/SCALING.md](docs/SCALING.md) for notes on going from this to 500+ req/s using vLLM, TensorRT-LLM, Triton, and NVIDIA Dynamo.

## ADRs

Six decision records in [docs/adr/](docs/adr/) covering cloud choice, IaC, network topology, SSH method, engine placement, and systemd vs Docker.

---

Pulkit Saraf - [pulkitsaraf.dev@gmail.com](mailto:pulkitsaraf.dev@gmail.com)
