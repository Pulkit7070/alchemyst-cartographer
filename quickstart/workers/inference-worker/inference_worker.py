import os
from typing import Any, Dict, List

from iii import InitOptions, Logger, register_worker
from transformers import AutoModelForCausalLM, AutoTokenizer

iii = register_worker(
    os.environ.get("III_URL", "ws://localhost:49134"),
    InitOptions(worker_name="inference-worker"),
)

logger = Logger()

model_id  = "ggml-org/gemma-3-270m-GGUF"
gguf_file = "gemma-3-270m-Q8_0.gguf"

tokenizer = AutoTokenizer.from_pretrained(model_id, gguf_file=gguf_file)
model     = AutoModelForCausalLM.from_pretrained(model_id, gguf_file=gguf_file)

tokenizer.chat_template = (
    """{{ bos_token }}"""
    """{%- if messages[0]['role'] == 'system' -%}"""
    """{%- if messages[0]['content'] is string -%}"""
    """{%- set first_user_prefix = messages[0]['content'] + '\n' -%}"""
    """{%- else -%}"""
    """{%- set first_user_prefix = messages[0]['content'][0]['text'] + '\n' -%}"""
    """{%- endif -%}"""
    """{%- set loop_messages = messages[1:] -%}"""
    """{%- else -%}"""
    """{%- set first_user_prefix = "" -%}"""
    """{%- set loop_messages = messages -%}"""
    """{%- endif -%}"""
    """{%- for message in loop_messages -%}"""
    """{%- if (message['role'] == 'user') != (loop.index0 % 2 == 0) -%}"""
    """{{ raise_exception("Conversation roles must alternate user/assistant/user/assistant/...") }}"""
    """{%- endif -%}"""
    """{%- if (message['role'] == 'assistant') -%}"""
    """{%- set role = "model" -%}"""
    """{%- else -%}"""
    """{%- set role = message['role'] -%}"""
    """{%- endif -%}"""
    """{{ '<start_of_turn>' + role + '\n' + (first_user_prefix if loop.first else "") }}"""
    """{%- if message['content'] is string -%}"""
    """{{ message['content'] | trim }}"""
    """{%- elif message['content'] is iterable -%}"""
    """{%- for item in message['content'] -%}"""
    """{%- if item['type'] == 'image' -%}"""
    """{{ '<start_of_image>' }}"""
    """{%- elif item['type'] == 'text' -%}"""
    """{{ item['text'] | trim }}"""
    """{%- endif -%}"""
    """{%- endfor -%}"""
    """{%- else -%}"""
    """{{ raise_exception("Invalid content type") }}"""
    """{%- endif -%}"""
    """{{ '<end_of_turn>\n' }}"""
    """{%- endfor -%}"""
    """{%- if add_generation_prompt -%}"""
    """{{'<start_of_turn>model\n'}}"""
    """{%- endif -%}"""
)


def run_inference_handler(payload: Dict[str, Any]) -> str:
    messages = payload.get("messages", [])
    text     = tokenizer.apply_chat_template(messages, tokenize=False, add_generation_prompt=True)
    inputs   = tokenizer(text, return_tensors="pt").to(model.device)
    max_new = int(os.environ.get("MAX_NEW_TOKENS", "256"))
    output   = model.generate(**inputs, max_new_tokens=max_new)
    result   = tokenizer.decode(output[0][inputs["input_ids"].shape[-1]:], skip_special_tokens=True)
    logger.info(f"inference::run_inference completed, output length={len(result)}")
    return result


iii.register_function("inference::run_inference", run_inference_handler)
print("Inference worker started - listening for calls to inference::run_inference")
