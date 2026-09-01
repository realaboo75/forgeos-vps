# ForgeOS VPS Architecture

## Overview

ForgeOS is an AI development platform running on an Oracle Cloud ARM64 VPS.
It provides a unified HTTPS entry point to multiple coding platforms, agent
orchestration tools, ML training pipelines, and model serving infrastructure.

```
┌──────────────────────────────────────────────────────────────────┐
│                     HTTPS (Tailscale Let's Encrypt)              │
│                     usaaboo-connect.tail22c6ab.ts.net            │
├──────────────────────────────────────────────────────────────────┤
│                          NGINX (443)                             │
│  HTTP→HTTPS redirect │ TLS termination │ Reverse proxy           │
├──────┬──────┬──────┬──────┬──────┬──────┬──────┬─────────────────┤
│  /   │/vscode│/omni │/trin │/term │ /ws  │/herm │/station │/munder│
│      │      │route │ity   │      │      │es    │         │       │
├──────┼──────┼──────┼──────┼──────┼──────┼──────┼─────────────────┤
│3000  │8443  │20128 │1517  │8767  │8766  │13133 │8090     │8420   │
│Dash  │VSC   │Route │Trin  │Term  │WSock │Hermes│Station  │Munder │
└──────┴──────┴──────┴──────┴──────┴──────┴──────┴─────────────────┘
```

## Hardware

| Spec | Value |
|------|-------|
| Provider | Oracle Cloud (Free Tier) |
| CPU | 2 vCPU (ARM64 Ampere Altra) |
| RAM | 12 GB |
| Swap | 4 GB (file-based, swappiness=10) |
| Disk | 200 GB boot volume |
| OS | Ubuntu 22.04 LTS (ARM64) |
| Network | Tailscale mesh VPN |

## Service Map

### Core Services

| Service | Port | Description | Technology |
|---------|------|-------------|------------|
| **Nginx** | 80, 443 | Reverse proxy, TLS termination | nginx/1.18 |
| **ForgeOS Dashboard** | 3000 | Platform launcher/control center | Vite + React SPA |
| **VS Code** | 8443 | Cloud IDE | code-server |
| **OmniRoute** | 20128 | Multi-provider LLM router | Node.js (omniroute) |
| **Trinity Backend** | 8000 | Agent orchestration API | Python/Uvicorn (Docker) |
| **Trinity Frontend** | 8090 | Agent dashboard | Vite (Docker) |
| **Terminal** | 8766-8767 | Web terminal (WS + HTTP) | Node.js |
| **Hermes** | 13133 | AI coding agent | Node.js |
| **Ollama** | 11434 | Local LLM inference | Ollama |

### ML Pipeline

| Service | Port | Description |
|---------|------|-------------|
| **Soup Serve** | 11435 | LoRA model serving (OpenAI-compatible) |
| **Training** | — | SmolLM2-135M LoRA fine-tuning (CPU) |

### Supporting Services

| Service | Port | Description |
|---------|------|-------------|
| **Redis** | 6379 | Trinity state/cache (Docker) |
| **OTel Collector** | 4317, 4318, 13133 | Observability (Docker) |
| **Vector** | 8686 | Log pipeline (Docker) |
| **Tailscale** | 41641 | Mesh VPN |

## Network Architecture

```
Internet
    │
    ▼
Tailscale (wg0)
    │
    ▼
Oracle Cloud VPS (64.181.211.201)
    │
    ├── Nginx (80/443) ─── TLS termination
    │     ├── /           → ForgeOS Dashboard (3000)
    │     ├── /vscode/    → code-server (8443)
    │     ├── /omniroute/ → OmniRoute (20128)
    │     ├── /trinity/   → Trinity Frontend (1517)
    │     ├── /terminal   → Terminal (8767)
    │     ├── /ws         → WebSocket (8766)
    │     ├── /hermes/    → Hermes (13133)
    │     ├── /station/   → Station (8090)
    │     └── /munder-*/  → Munder Difflin (8420)
    │
    ├── Docker Networks
    │     ├── default     → Trinity Backend, Frontend, Agent containers
    │     ├── platform    → Redis, OTel, Vector, Scheduler
    │     └── kortix      → Supabase/Kortix stack
    │
    └── Host Services
          ├── Ollama (11434)
          └── Soup Serve (11435)
```

## Security Model

1. **No public HTTP** — All HTTP (80) redirects to HTTPS (443)
2. **TLS** — Tailscale-managed Let's Encrypt certificates, auto-renewed weekly
3. **Internal binding** — Most services bind to 127.0.0.1 only
4. **Tailscale** — All access through mesh VPN (no direct internet exposure of backends)
5. **Docker** — Containers use custom bridge networks, least-privilege
6. **No secrets in code** — All credentials in `.env` or environment variables

## Data Flow: ML Training → Inference

```
1. User uploads dataset.jsonl to pipeline directory
2. train_135m.py runs:
   a. Loads SmolLM2-135M base model
   b. Applies LoRA adapter (r=4, alpha=8)
   c. Fine-tunes for 3 epochs on dataset
   d. Saves adapter + tokenizer to output/trained/
   e. Starts OpenAI-compatible HTTP server on :11435
3. OmniRoute routes requests to localhost:11435
4. Client sends chat completion request → OmniRoute → Soup → response
```

## Resource Allocation

| Resource | Used By | Allocation |
|----------|---------|------------|
| RAM (8.5 GB) | Docker containers (~4 GB), Ollama (~1.5 GB), Soup (~1.6 GB), OS (~1.5 GB) |
| Swap (2.5 GB) | Overflow for model loading |
| CPU (2 cores) | Training (when active), inference, Docker workloads |
| Disk (81 GB) | Docker images (~30 GB), models (~4 GB), OS + apps (~47 GB) |