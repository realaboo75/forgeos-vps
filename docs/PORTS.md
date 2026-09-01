# ForgeOS VPS — Port Reference

## Nginx Entry Points (via HTTPS)

| Path | Backend Port | Service |
|------|-------------|---------|
| `/` | 3000 | ForgeOS Dashboard |
| `/vscode/` | 8443 | code-server (VS Code) |
| `/omniroute/` | 20128 | OmniRoute LLM Router |
| `/trinity/` | 1517 | Trinity Frontend |
| `/terminal` | 8767 | Terminal (HTTP) |
| `/ws` | 8766 | Terminal (WebSocket) |
| `/hermes/` | 13133 | Hermes Agent |
| `/station/` | 8090 | Station (Workstation) |
| `/munder-difflin/` | 8420 | Munder Difflin |

## Direct Ports (localhost only)

| Port | Service | Protocol |
|------|---------|----------|
| 3000 | ForgeOS Dashboard (Vite SPA) | HTTP |
| 6379 | Redis (Trinity) | TCP |
| 8000 | Trinity Backend (Uvicorn) | HTTP |
| 8080 | Trinity MCP Server | HTTP |
| 8090 | Trinity Frontend | HTTP |
| 8420 | Munder Difflin | HTTP |
| 8443 | code-server (VS Code) | HTTP |
| 8686 | Vector (log pipeline) | HTTP |
| 8766 | Terminal WebSocket | WS |
| 8767 | Terminal HTTP | HTTP |
| 8889 | OTel Collector | HTTP |
| 11434 | Ollama | HTTP |
| 11435 | Soup Serve (ML inference) | HTTP |
| 13133 | OTel Collector / Hermes proxy | HTTP |
| 13737 | Kortix Frontend | HTTP |
| 13738 | Kortix API | HTTP |
| 13740 | Supabase Kong | HTTP |
| 13741 | Supabase Supavisor (pg) | TCP |
| 13742 | Supabase Supavisor (pool) | TCP |
| 20128 | OmniRoute Dashboard | HTTP |

## Docker Container Ports

| Container | Internal Port | Host Port | Network |
|-----------|--------------|-----------|---------|
| trinity-backend | 8000 | 127.0.0.1:8000 | default |
| trinity-frontend | 80 | 0.0.0.0:8090 | default |
| trinity-redis | 6379 | 127.0.0.1:6379 | platform |
| trinity-mcp-server | 8080 | 0.0.0.0:8080 | default |
| trinity-otel-collector | 4317,4318,8889,13133 | 0.0.0.0 | default |
| trinity-vector | 8686 | 0.0.0.0:8686 | default |