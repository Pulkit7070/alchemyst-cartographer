# Runbook

Operational procedures for the Alchemyst Cloud Cartographer deployment.

---

## SSH Access (IAP only - no public port 22)

```bash
# Gateway VM
gcloud compute ssh gateway-vm \
  --tunnel-through-iap \
  --zone=asia-south1-a \
  --project=<PROJECT_ID>

# Inference VM (private - no public IP; IAP tunnels through Google's network)
gcloud compute ssh inference-vm \
  --tunnel-through-iap \
  --zone=asia-south1-a \
  --project=<PROJECT_ID>
```

---

## Tailing Logs

```bash
# On gateway VM - iii engine
sudo journalctl -fu iii-engine --output=cat

# On gateway VM - caller worker (HTTP layer)
sudo journalctl -fu caller-worker --output=cat

# On inference VM - model worker
sudo journalctl -fu inference-worker --output=cat

# From your laptop via Cloud Logging
gcloud logging read \
  'resource.type="gce_instance" severity>=WARNING' \
  --project=<PROJECT_ID> \
  --limit=50 \
  --format=json
```

---

## Service Management

```bash
# Restart a service
sudo systemctl restart inference-worker

# Check service status
sudo systemctl status inference-worker

# Check if engine is registered and listening
sudo ss -tlnp | grep 49134   # on gateway-vm
```

---

## Redeploy App (no infra rebuild)

```bash
# 1. Bundle new version
bash scripts/bundle.sh <PROJECT_ID> $(git rev-parse --short HEAD)

# 2. SSH to each VM and pull + restart
# Gateway:
gcloud compute ssh gateway-vm --tunnel-through-iap --zone=asia-south1-a \
  --command="
    sudo gsutil cp gs://<PROJECT_ID>-app-bundles/app-latest.tar.gz /opt/alchemyst/app.tar.gz
    sudo tar -xzf /opt/alchemyst/app.tar.gz -C /opt/alchemyst/
    sudo chown -R alchemyst:alchemyst /opt/alchemyst
    sudo systemctl restart iii-engine caller-worker
  "

# Inference:
gcloud compute ssh inference-vm --tunnel-through-iap --zone=asia-south1-a \
  --command="
    sudo gsutil cp gs://<PROJECT_ID>-app-bundles/app-latest.tar.gz /opt/alchemyst/app.tar.gz
    sudo tar -xzf /opt/alchemyst/app.tar.gz -C /opt/alchemyst/
    sudo chown -R alchemyst:alchemyst /opt/alchemyst
    sudo systemctl restart inference-worker
  "
```

---

## Rollback

```bash
# Deploy a specific version (git SHA must exist in GCS)
make deploy PROJECT_ID=<id> app_version=<old-sha>

# Or via Terraform directly
cd terraform && terraform apply \
  -var="project_id=<PROJECT_ID>" \
  -var="app_version=<old-sha>"
```

---

## Debugging: API returns 502/503

1. Check caller-worker is running on gateway: `sudo systemctl status caller-worker`
2. Check iii engine is running: `sudo systemctl status iii-engine`
3. Check engine is listening: `sudo ss -tlnp | grep 49134`
4. Check inference worker is connected (SSH to inference-vm): `sudo systemctl status inference-worker`
5. Check engine logs for registration errors: `sudo journalctl -fu iii-engine --since "5 min ago"`
6. Try calling inference directly via RPC (from gateway-vm):
   ```bash
   curl -X POST http://127.0.0.1:3111/v1/chat/completions \
     -H "Content-Type: application/json" \
     -d '{"messages":[{"role":"user","content":"ping"}]}'
   ```

---

## Model Cache Management

The model is downloaded from HuggingFace on first start of inference-worker.
This takes ~5 min. Subsequent starts use the cache at `/opt/alchemyst/.cache/huggingface`.

To pre-warm the cache before going live:
```bash
# On inference-vm
sudo -u alchemyst /opt/alchemyst/venv/bin/python -c "
from transformers import AutoTokenizer
AutoTokenizer.from_pretrained('ggml-org/gemma-3-270m-GGUF')
print('cache warmed')
"
```

---

## Full Redeploy (from scratch on a new GCP project)

```bash
# 1. Set project
gcloud config set project <NEW_PROJECT_ID>

# 2. Bootstrap
make bootstrap PROJECT_ID=<NEW_PROJECT_ID>

# 3. Init Terraform with new backend
cd terraform
terraform init \
  -backend-config="bucket=<NEW_PROJECT_ID>-tf-state" \
  -backend-config="prefix=cloud-cartographer" \
  -reconfigure

# 4. Deploy (uploads bundle + applies infra)
make deploy PROJECT_ID=<NEW_PROJECT_ID>

# 5. Smoke test
make smoke
```
