#!/usr/bin/env python3
"""SmolLM2-135M Training + Serve — self-contained script."""

import os
import sys
import json
import time
import torch
import psutil
from transformers import (
    AutoModelForCausalLM, AutoTokenizer, TrainingArguments, Trainer,
    DataCollatorForLanguageModeling,
)
from peft import LoraConfig, get_peft_model
from datasets import load_dataset
from http.server import HTTPServer, BaseHTTPRequestHandler

# ── Configuration ──────────────────────────────────────────
MODEL_ID = os.environ.get("SOUP_MODEL_ID", "HuggingFaceTB/SmolLM2-135M")
PIPELINE_DIR = os.environ.get(
    "SOUP_PIPELINE_DIR",
    "/home/ubuntu/forgeos-projects/soup-cli/pipeline",
)
DATASET_PATH = os.path.join(PIPELINE_DIR, "dataset.jsonl")
OUTPUT_DIR = os.path.join(PIPELINE_DIR, "output", "trained")
LOG_FILE = os.path.join(PIPELINE_DIR, "pipeline_e2e.log")
STATUS_FILE = os.path.join(PIPELINE_DIR, "status.json")
PORT = int(os.environ.get("SOUP_SERVE_PORT", "11435"))


def log(msg):
    line = f"[T] {msg}"
    print(line, flush=True)
    with open(LOG_FILE, "a") as f:
        f.write(line + "\n")


def update_status(status, **kw):
    try:
        with open(STATUS_FILE, "w") as f:
            json.dump(
                {"status": status, "ts": time.strftime("%Y-%m-%dT%H:%M:%S"), **kw}, f
            )
    except Exception:
        pass


# ── Training ───────────────────────────────────────────────
update_status("training", progress=5)
log("SmolLM2-135M Training + Serve")
log("RAM: %.1fGB Swap: %.1fGB" % (psutil.virtual_memory().used / 1024**3, psutil.swap_memory().used / 1024**3)))

tokenizer = AutoTokenizer.from_pretrained(MODEL_ID, trust_remote_code=True)
if tokenizer.pad_token is None:
    tokenizer.pad_token = tokenizer.eos_token

model = AutoModelForCausalLM.from_pretrained(
    MODEL_ID, trust_remote_code=True, torch_dtype=torch.float32, device_map="cpu", low_cpu_mem_usage=True
)
log("Model: %.1fM params" % (model.num_parameters() / 1e6,))
update_status("training", progress=20)

lora_config = LoraConfig(
    r=4, lora_alpha=8, lora_dropout=0.05,
    target_modules=["q_proj", "v_proj"], task_type="CAUSAL_LM",
)
model = get_peft_model(model, lora_config)
model.print_trainable_parameters()
update_status("training", progress=25)

ds = load_dataset("json", data_files=DATASET_PATH, split="train")
log("Dataset: %d examples" % len(ds))


def tokenize_fn(examples):
    texts = []
    for msgs in examples["messages"]:
        parts = []
        for m in msgs:
            parts.append("<|%s|>\n%s<|end|>\n" % (m["role"], m["content"]))
        parts.append("<|assistant|>\n")
        texts.append("".join(parts))
    return tokenizer(texts, truncation=True, max_length=128, padding="max_length")


ds = ds.map(tokenize_fn, batched=True, remove_columns=ds.column_names)
update_status("training", progress=30)

training_args = TrainingArguments(
    output_dir=OUTPUT_DIR,
    num_train_epochs=3,
    per_device_train_batch_size=1,
    gradient_accumulation_steps=4,
    learning_rate=3e-4,
    warmup_ratio=0.1,
    weight_decay=0.01,
    logging_steps=2,
    save_steps=50,
    save_total_limit=1,
    fp16=False,
    bf16=False,
    no_cuda=True,
    dataloader_num_workers=0,
    report_to="none",
    remove_unused_columns=False,
    lr_scheduler_type="cosine",
)

trainer = Trainer(
    model=model,
    args=training_args,
    train_dataset=ds,
    data_collator=DataCollatorForLanguageModeling(tokenizer=tokenizer, mlm=False),
)
update_status("training", progress=40)
log("Starting training...")

t0 = time.time()
trainer.train()
log("Training done in %ds" % int(time.time() - t0))
update_status("training", progress=70)

# Save
os.makedirs(OUTPUT_DIR, exist_ok=True)
model.save_pretrained(OUTPUT_DIR)
tokenizer.save_pretrained(OUTPUT_DIR)
log("Saved to %s" % OUTPUT_DIR)
update_status("training", progress=100)

# ── Evaluation (simple) ───────────────────────────────────
log("Evaluation...")
test_prompts = [
    "How do I check memory usage?",
    "What is the best Linux command for disk space?",
    "Explain what a container is.",
]
for p in test_prompts:
    inputs = tokenizer(p, return_tensors="pt")
    with torch.no_grad():
        out = model.generate(**inputs, max_new_tokens=50, do_sample=False)
    resp = tokenizer.decode(out[0][inputs["input_ids"].shape[1]:], skip_special_tokens=True)
    log("Q: %s -> A: %s" % (p, resp[:80]))

# ── Serve ──────────────────────────────────────────────────
log("Starting serve on port %d..." % PORT)
update_status("serving")


class Handler(BaseHTTPRequestHandler):
    def log_message(self, *a):
        pass

    def do_GET(self):
        if self.path == "/health":
            self.send_response(200)
            self.send_header("Content-Type", "application/json")
            self.end_headers()
            self.wfile.write(json.dumps({"status": "ok", "model": "forgeos/smollm2-trained"}).encode())
        elif self.path == "/v1/models":
            data = {"object": "list", "data": [{"id": "forgeos/smollm2-trained", "object": "model", "owned_by": "forgeos"}]}
            self.send_response(200)
            self.send_header("Content-Type", "application/json")
            self.end_headers()
            self.wfile.write(json.dumps(data).encode())
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
                out = model.generate(**inputs, max_new_tokens=max_tokens, do_sample=True, temperature=0.7, top_p=0.9)
            resp_text = tokenizer.decode(out[0][inputs["input_ids"].shape[1]:], skip_special_tokens=True)
            data = {
                "id": "cmpl-forgeos",
                "object": "chat.completion",
                "choices": [{"index": 0, "message": {"role": "assistant", "content": resp_text}, "finish_reason": "stop"}],
                "usage": {
                    "prompt_tokens": int(inputs["input_ids"].shape[1]),
                    "completion_tokens": int(out.shape[1] - inputs["input_ids"].shape[1]),
                    "total_tokens": int(out.shape[1]),
                },
            }
            self.send_response(200)
            self.send_header("Content-Type", "application/json")
            self.end_headers()
            self.wfile.write(json.dumps(data).encode())
        else:
            self.send_response(404)
            self.end_headers()


HTTPServer(("0.0.0.0", PORT), Handler).serve_forever()