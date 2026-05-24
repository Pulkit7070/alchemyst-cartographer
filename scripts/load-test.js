// k6 load test - run with: k6 run scripts/load-test.js --env API_URL=http://<ip>:3111
import http from "k6/http";
import { check, sleep } from "k6";
import { Trend, Rate } from "k6/metrics";

const latency = new Trend("inference_latency_ms", true);
const errorRate = new Rate("error_rate");

export const options = {
  stages: [
    { duration: "30s", target: 5 },   // ramp up
    { duration: "60s", target: 10 },  // steady state
    { duration: "30s", target: 0 },   // ramp down
  ],
  thresholds: {
    inference_latency_ms: ["p(95)<5000"], // p95 under 5s for a 270M CPU model
    error_rate: ["rate<0.05"],            // < 5% errors
  },
};

const API_URL = __ENV.API_URL || "http://localhost:3111";

export default function () {
  const payload = JSON.stringify({
    messages: [{ role: "user", content: "What is the capital of France? One word." }],
  });

  const res = http.post(`${API_URL}/v1/chat/completions`, payload, {
    headers: { "Content-Type": "application/json" },
    timeout: "120s",
  });

  const ok = check(res, {
    "status 200": (r) => r.status === 200,
    "has choices": (r) => {
      try {
        return JSON.parse(r.body).choices !== undefined;
      } catch {
        return false;
      }
    },
  });

  latency.add(res.timings.duration);
  errorRate.add(!ok);

  sleep(1);
}
