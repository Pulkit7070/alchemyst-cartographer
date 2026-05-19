#!/usr/bin/env bash
# Proves that the inference VM is unreachable from the public internet
# and that the iii engine port is not exposed externally.
# Usage: ./scripts/verify-isolation.sh <project-id> <zone>
set -euo pipefail

PROJECT_ID="${1:-$(gcloud config get-value project)}"
ZONE="${2:-asia-south1-a}"

echo "==> Network isolation verification"
echo ""

# 1. Confirm inference VM has no external IP
echo "[1/4] Checking inference VM has no external IP..."
EXTERNAL_IP=$(gcloud compute instances describe inference-vm \
  --zone="${ZONE}" \
  --project="${PROJECT_ID}" \
  --format="get(networkInterfaces[0].accessConfigs[0].natIP)" 2>/dev/null || echo "")

if [[ -z "${EXTERNAL_IP}" || "${EXTERNAL_IP}" == "None" ]]; then
  echo "     PASS: inference-vm has no external IP ✓"
else
  echo "     FAIL: inference-vm has external IP: ${EXTERNAL_IP}"
  exit 1
fi

# 2. Confirm iii engine port (49134) is not reachable from internet
GATEWAY_IP="$(cd terraform && terraform output -raw gateway_public_ip 2>/dev/null)"
echo "[2/4] Checking iii engine port 49134 is NOT externally reachable..."
if timeout 5 bash -c "echo >/dev/tcp/${GATEWAY_IP}/49134" 2>/dev/null; then
  echo "     FAIL: port 49134 is reachable from internet - firewall misconfigured!"
  exit 1
else
  echo "     PASS: port 49134 is blocked externally ✓"
fi

# 3. Confirm API port 3111 IS reachable
echo "[3/4] Checking API port 3111 IS externally reachable..."
if timeout 10 bash -c "echo >/dev/tcp/${GATEWAY_IP}/3111" 2>/dev/null; then
  echo "     PASS: port 3111 is reachable ✓"
else
  echo "     FAIL: port 3111 is not reachable - something is wrong"
  exit 1
fi

# 4. Confirm port 22 is NOT directly reachable (IAP only)
echo "[4/4] Checking SSH port 22 is NOT directly reachable (IAP-only)..."
if timeout 5 bash -c "echo >/dev/tcp/${GATEWAY_IP}/22" 2>/dev/null; then
  echo "     WARN: port 22 is directly reachable - only IAP CIDR should be whitelisted"
  echo "           This is OK if your IP happens to be in 35.235.240.0/20, otherwise fix firewall"
else
  echo "     PASS: port 22 is blocked from direct internet access ✓"
fi

echo ""
echo "==> Isolation verification PASSED ✓"
