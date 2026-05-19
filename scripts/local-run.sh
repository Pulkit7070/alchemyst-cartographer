#!/usr/bin/env bash
# Run the full stack locally: iii engine + inference worker + caller worker.
# Prerequisites:
#   - iii CLI: curl -fsSL https://install.iii.dev/iii/main/install.sh | sh
#     (on Windows Git Bash: TARGET=x86_64-pc-windows-msvc bash -c "$(curl ...)")
#   - node 20+, python 3.11+
# Usage: bash scripts/local-run.sh
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_DIR="$(cd "${SCRIPT_DIR}/.." && pwd)"
QUICKSTART_DIR="${REPO_DIR}/quickstart"
VENV_DIR="${REPO_DIR}/venv"
HF_CACHE="${REPO_DIR}/.cache/huggingface"

export PATH="${HOME}/.local/bin:${HOME}/bin:${PATH}"

echo "==> Checking prerequisites..."
command -v iii  >/dev/null || { echo "ERROR: iii not found."; echo "  Install: TARGET=x86_64-pc-windows-msvc bash -c \"\$(curl -fsSL https://install.iii.dev/iii/main/install.sh)\""; exit 1; }
command -v node >/dev/null || { echo "ERROR: node 20+ required"; exit 1; }

PYTHON="${VENV_DIR}/Scripts/python.exe"
[[ -f "${PYTHON}" ]] || PYTHON="${VENV_DIR}/bin/python"
if [[ ! -f "${PYTHON}" ]]; then
  echo "==> Creating venv..."
  python3 -m venv "${VENV_DIR}" 2>/dev/null || python -m venv "${VENV_DIR}"
fi

echo "==> Installing caller-worker deps..."
cd "${QUICKSTART_DIR}/workers/caller-worker"
npm install --silent

echo "==> Installing inference-worker deps..."
"${PYTHON}" -m pip install --quiet \
  "iii-sdk==0.11.0" "gguf>=0.10.0" transformers accelerate torch watchfiles 2>/dev/null || true

echo "==> Starting iii engine (built-in HTTP on :3111, WS on :49134)..."
cd "${QUICKSTART_DIR}"

cleanup() {
  echo ""
  echo "==> Stopping all services..."
  kill "${ENGINE_PID:-}" "${INF_PID:-}" "${CALLER_PID:-}" 2>/dev/null || true
}
trap cleanup EXIT

III_TELEMETRY_ENABLED=false iii --use-default-config --no-update-check \
  > /tmp/iii-engine.log 2>&1 &
ENGINE_PID=$!

for i in $(seq 1 10); do
  STATUS=$(curl -so /dev/null -w "%{http_code}" http://127.0.0.1:3111/ 2>/dev/null || echo "000")
  [[ "${STATUS}" != "000" ]] && echo "    Engine ready (poll ${i})" && break
  [[ $i -eq 10 ]] && { echo "ERROR: engine did not start"; cat /tmp/iii-engine.log | tail -5; exit 1; }
  sleep 2
done

echo "==> Starting inference worker (first run downloads ~241 MB)..."
cd "${QUICKSTART_DIR}/workers/inference-worker"
TRANSFORMERS_OFFLINE=0 PYTHONUNBUFFERED=1 \
  III_URL="ws://127.0.0.1:49134" \
  HF_HOME="${HF_CACHE}" \
  MAX_NEW_TOKENS="${MAX_NEW_TOKENS:-32}" \
  "${PYTHON}" -u inference_worker.py > /tmp/inference-worker.log 2>&1 &
INF_PID=$!

echo "==> Starting caller worker..."
cd "${QUICKSTART_DIR}/workers/caller-worker"
III_URL="ws://127.0.0.1:49134" node --import tsx/esm src/worker.ts \
  > /tmp/caller-worker.log 2>&1 &
CALLER_PID=$!

echo "==> Waiting for model to load (~10-60s depending on cache)..."
for i in $(seq 1 30); do
  if grep -q "Inference worker started" /tmp/inference-worker.log 2>/dev/null; then
    echo "    Model ready (poll ${i})"
    break
  fi
  [[ $i -eq 30 ]] && { echo "ERROR: inference worker did not start"; cat /tmp/inference-worker.log | tail -10; exit 1; }
  sleep 5
done

echo ""
echo "==> Smoke test: GET /healthz"
curl -fsS http://127.0.0.1:3111/healthz

echo ""
echo "==> Smoke test: POST /v1/chat/completions"
RESPONSE=$(curl -fsS -X POST http://127.0.0.1:3111/v1/chat/completions \
  -H "Content-Type: application/json" \
  -d '{"messages":[{"role":"user","content":"What is 2+2? Answer with just the number."}]}' \
  --max-time 30)

echo "${RESPONSE}"
CONTENT=$(echo "${RESPONSE}" | "${PYTHON}" -c \
  "import sys,json; print(json.load(sys.stdin)['choices'][0]['message']['content'])" 2>/dev/null || echo "(parse error)")

echo ""
echo "==> Model replied: '${CONTENT}'"
echo "==> LOCAL RUN PASSED ✓"
echo ""
echo "    API endpoint: http://127.0.0.1:3111/v1/chat/completions"
echo "    Press Ctrl+C to stop."
wait
