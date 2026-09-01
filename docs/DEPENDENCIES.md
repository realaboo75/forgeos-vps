# ForgeOS VPS — Service Dependencies

## Startup Order

```
1. System Services
   ├── Docker Engine
   ├── Nginx
   ├── Ollama
   └── Tailscale

2. Docker Stacks
   ├── Redis → Trinity Backend → Trinity Frontend
   ├── OTel Collector → Vector
   └── Kortix/Supabase stack

3. Host Services
   ├── code-server (VS Code)
   ├── OmniRoute
   ├── Hermes
   └── Terminal

4. ML Pipeline (on demand)
   ├── train_135m.py → Soup Serve (11435)
   └── OmniRoute routes to 11435
```

## Dependency Graph

```
ForgeOS Dashboard (3000)
    └── depends on: nginx, Tailscale

Trinity Backend (8000)
    ├── depends on: Redis (6379)
    ├── depends on: Docker socket
    └── env: REDIS_URL, INTERNAL_API_SECRET

Trinity Frontend (8090)
    └── depends on: Trinity Backend

OmniRoute (20128)
    ├── depends on: OpenRouter API key
    ├── connects to: Soup (11435) for local models
    └── connects to: External providers

Soup Serve (11435)
    ├── depends on: trained model artifact
    ├── depends on: torch, transformers, peft
    └── started by: train_135m.py or manually

Hermes (13133)
    └── depends on: API keys (Nous, OpenRouter, etc.)

code-server (8443)
    └── no dependencies

Terminal (8766-8767)
    └── no dependencies
```