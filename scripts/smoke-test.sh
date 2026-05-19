#!/usr/bin/env bash
# Validates the API end-to-end. Exits 0 on success, 1 on failure.
# Usage: ./scripts/smoke-test.sh [api-url]
set -euo pipefail

API_URL="${1:-$(cd terraform && terraform output -raw api_url 2>/dev/null)}"

if [[ -z "${API_URL}" ]]; then
  echo "ERROR: API_URL not set. Pass as argument or run from repo root after terraform apply."
  exit 1
fi

echo "==> Smoke test against: ${API_URL}"
echo "==> Waiting for API to be ready..."

# Retry up to 30 times with 10s gap (5 min total — VMs take time to boot)
for i in $(seq 1 30); do
  STATUS=$(curl -so /dev/null -w "%{http_code}" \
    --connect-timeout 5 \
    "${API_URL}/healthz" 2>/dev/null || echo "000")
  if [[ "${STATUS}" == "200" ]]; then
    break
  fi
  echo "  attempt ${i}/30 — got ${STATUS}, retrying in 10s..."
  sleep 10
done

echo "==> Running inference test..."
RESPONSE=$(curl -fsS \
  --connect-timeout 10 \
  --max-time 120 \
  -X POST "${API_URL}/v1/chat/completions" \
  -H "Content-Type: application/json" \
  -d '{"messages":[{"role":"user","content":"Reply with exactly the word: WORKING"}]}')

echo "Response:"
echo "${RESPONSE}" | jq .

# Validate OpenAI-compatible response schema
FAIL=0
for field in '.id' '.object' '.model' '.choices' '.choices[0].message.role' '.choices[0].message.content' '.choices[0].finish_reason'; do
  val=$(echo "${RESPONSE}" | jq -e "${field}" 2>/dev/null) || { echo "FAIL: missing field ${field}"; FAIL=1; }
done
[[ "${FAIL}" -eq 1 ]] && exit 1

OBJECT=$(echo "${RESPONSE}"  | jq -r '.object')
[[ "${OBJECT}" == "chat.completion" ]] || { echo "FAIL: .object should be 'chat.completion', got '${OBJECT}'"; exit 1; }

CONTENT=$(echo "${RESPONSE}" | jq -r '.choices[0].message.content')
echo ""
echo "==> Model replied: ${CONTENT}"
echo "==> Smoke test PASSED ✓"
