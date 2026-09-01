#!/usr/bin/env python3
"""Soup — OpenAI-compatible inference server for trained models."""

import os
import json
import sys
import time
import torch
from http.server import HTTPServer, BaseHTTPRequestHandler
from transformers import AutoModelForCausalLM, AutoTokenizer

# ── Configuration ──────────────────────────────────────────
TRAINED_DIR = os.environ.get(
    "SOUP_TRAINED_DIR",
    "/home/ubuntu/forgeos-projects/soup-cli/pipeline/output/trained",
)
PORT = int(os.environ.get("SOUP_SERVE_PORT", "11435"))
STATUS_FILE = os.environ.get(
    "SOUP_STATUS_FILE",
    "/home/ubuntu/forgeos-projects/soup-cli/pipeline/status.json",
)
MODEL_NAME = os.environ.get("SOUP_MODEL_NAME", "forgeos/smollm2-trained")


def log(msg):
    ts = time.strftime("%Y-%m-%d %H:%M:%S")
    print(f"[{ts}] {msg}", flush=True)


def update_status(status, **extra):
    try:
        with open(STATUS_FILE, "w") as f:
            json.dump(
                {"status": status, "ts": time.strftime("%Y-%m-%dT%H:%M:%S"), **extra},
                f,
            )
    except Exception:
        pass


# ── Load Model ─────────────────────────────────────────────
if not os.path.exists(TRAINED_DIR):
    log(f"ERROR: Trained model not found at {TRAINED_DIR}")
    sys.exit(1)

log(f"Loading model from {TRAINED_DIR}...")
tokenizer = AutoTokenizer.from_pretrained(TRAINED_DIR, trust_remote_code=True)
model = AutoModelForCausalLM.from_pretrained(
    TRAINED_DIR,
    trust_remote_code=True,
    torch_dtype=torch.float32,
    device_map="cpu",
    low_cpu_mem_usage=True,
)
model.eval()
log(f"Model loaded. Serving on port {PORT}")

update_status("serving")


# ── HTTP Handler ───────────────────────────────────────────
class Handler(BaseHTTPRequestHandler):
    def log_message(self, *a):
        pass

    def do_GET(self):
        if self.path == "/health":
            self._json_response(200, {"status": "ok", "model": MODEL_NAME})
        elif self.path == "/v1/models":
            self._json_response(
                200,
                {
                    "object": "list",
                    "data": [
                        {"id": MODEL_NAME, "object": "model", "owned_by": "forgeos"}
                    ],
                },
            )
        else:
            self.send_response(404)
            self.end_headers()

    def do_POST(self):
        if self.path in ("/v1/chat/completions", "/v1/completions"):
            length = int(self.headers.get("Content-Length", 0))
            body = json.loads(self.rfile.read(length))
            messages = body.get("messages", [])
            prompt = messages[-1].get("content", "") if messages else body.get("prompt", "")
            max_tokens = body.get("max_tokens", 200)

            inputs = tokenizer(prompt, return_tensors="pt")
            with torch.no_grad():
                out = model.generate(
                    **inputs,
                    max_new_tokens=max_tokens,
                    do_sample=True,
                    temperature=0.7,
                    top_p=0.9,
                )
            resp_text = tokenizer.decode(
                out[0][inputs["input_ids"].shape[1] :], skip_special_tokens=True
            )

            self._json_response(
                200,
                {
                    "id": "cmpl-forgeos",
                    "object": "chat.completion",
                    "choices": [
                        {
                            "index": 0,
                            "message": {"role": "assistant", "content": resp_text},
                            "finish_reason": "stop",
                        }
                    ],
                    "usage": {
                        "prompt_tokens": int(inputs["input_ids"].shape[1]),
                        "completion_tokens": int(
                            out.shape[1] - inputs["input_ids"].shape[1]
                        ),
                        "total_tokens": int(out.shape[1]),
                    },
                },
            )
        else:
            self.send_response(404)
            self.end_headers()

    def _json_response(self, code, data):
        self.send_response(code)
        self.send_header("Content-Type", "application/json")
        self.end_headers()
        self.wfile.write(json.dumps(data).encode())


# ── Start Server ───────────────────────────────────────────
log(f"Starting server on 0.0.0.0:{PORT}")
HTTPServer(("0.0.0.0", PORT), Handler).serve_forever()