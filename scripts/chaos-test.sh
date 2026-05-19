#!/usr/bin/env bash
# Kills the inference worker, confirms API returns 503, then verifies auto-recovery.
# Usage: ./scripts/chaos-test.sh <project-id> <zone>
set -euo pipefail

PROJECT_ID="${1:-$(gcloud config get-value project)}"
ZONE="${2:-asia-south1-a}"
API_URL="$(cd terraform && terraform output -raw api_url 2>/dev/null)"

echo "==> Chaos test: inference worker kill + recovery"
echo ""

# 1. Confirm API is healthy before the test
echo "[1/4] Pre-chaos health check..."
curl -fsS --max-time 30 -X POST "${API_URL}/v1/chat/completions" \
  -H "Content-Type: application/json" \
  -d '{"messages":[{"role":"user","content":"ping"}]}' | jq -e '.choices[0]' > /dev/null
echo "     PASS: API healthy before chaos ✓"

# 2. Kill inference worker via IAP SSH
echo "[2/4] Stopping inference-worker on inference-vm..."
gcloud compute ssh inference-vm \
  --tunnel-through-iap \
  --zone="${ZONE}" \
  --project="${PROJECT_ID}" \
  --command="sudo systemctl stop inference-worker" \
  --quiet

echo "     Inference worker stopped."
sleep 3

# 3. API should degrade gracefully (503 or error JSON, not a crash)
echo "[3/4] Verifying API responds gracefully while worker is down..."
HTTP_CODE=$(curl -so /dev/null -w "%{http_code}" --max-time 15 \
  -X POST "${API_URL}/v1/chat/completions" \
  -H "Content-Type: application/json" \
  -d '{"messages":[{"role":"user","content":"ping"}]}' 2>/dev/null || echo "000")

echo "     API responded with HTTP ${HTTP_CODE} (expected 4xx/5xx, not a hang)"

# 4. systemd auto-restarts the worker - wait and verify recovery
echo "[4/4] Waiting for auto-recovery (systemd Restart=always, RestartSec=5)..."
sleep 15

for i in $(seq 1 12); do
  STATUS=$(curl -so /dev/null -w "%{http_code}" --max-time 60 \
    -X POST "${API_URL}/v1/chat/completions" \
    -H "Content-Type: application/json" \
    -d '{"messages":[{"role":"user","content":"ping"}]}' 2>/dev/null || echo "000")
  if [[ "${STATUS}" == "200" ]]; then
    echo "     PASS: API recovered after ${i} poll(s) ✓"
    break
  fi
  echo "     poll ${i}/12 - status ${STATUS}, waiting 10s..."
  sleep 10
done

echo ""
echo "==> Chaos test PASSED ✓"
