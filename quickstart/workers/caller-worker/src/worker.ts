import { registerWorker } from "iii-sdk";

const engineUrl = process.env.III_URL ?? "ws://localhost:49134";
const iii = registerWorker(engineUrl);

// RPC bridge - callable by other workers
iii.registerFunction(
  "inference::get_response",
  async (payload: { messages: Array<{ role: string; content: string }> }) => {
    return await iii.trigger({
      function_id: "inference::run_inference",
      payload,
    });
  }
);

// HTTP handler - receives POST /v1/chat/completions
iii.registerFunction(
  "http::run_inference_over_http",
  async (req: Record<string, unknown>) => {
    // iii may pass the parsed JSON body directly as req, or nested under req.body
    let parsed: Record<string, unknown>;
    if (req?.body != null) {
      parsed = typeof req.body === "string"
        ? (JSON.parse(req.body as string) as Record<string, unknown>)
        : (req.body as Record<string, unknown>);
    } else {
      parsed = req;
    }

    const messages = parsed.messages as Array<{ role: string; content: string }>;

    const result = await iii.trigger({
      function_id: "inference::run_inference",
      payload: { messages },
    });

    const content =
      typeof result === "string"
        ? result
        : (result as Record<string, unknown>)?.output ?? JSON.stringify(result);

    return {
      status_code: 200,
      headers: {
        "Content-Type": "application/json",
        "Access-Control-Allow-Origin": "*",
      },
      body: JSON.stringify({
        id: `chatcmpl-${Date.now()}`,
        object: "chat.completion",
        created: Math.floor(Date.now() / 1000),
        model: "gemma-3-270m",
        choices: [
          {
            index: 0,
            message: { role: "assistant", content },
            finish_reason: "stop",
          },
        ],
      }),
    };
  }
);

// Health check
iii.registerFunction("http::healthz", async () => ({
  status_code: 200,
  headers: { "Content-Type": "application/json" },
  body: JSON.stringify({ status: "ok", model: "gemma-3-270m" }),
}));

// HTTP triggers
iii.registerTrigger({
  type: "http",
  function_id: "http::run_inference_over_http",
  config: { api_path: "/v1/chat/completions", http_method: "POST" },
});

iii.registerTrigger({
  type: "http",
  function_id: "http::healthz",
  config: { api_path: "/healthz", http_method: "GET" },
});
