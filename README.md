# ForgeOS VPS

Reproducible configuration and deployment blueprint for the ForgeOS Oracle Cloud VPS — an AI development platform with multi-service orchestration, ML training pipelines, and unified HTTPS access.

## What's Inside

```
forgeos-vps/
├── configs/
│   ├── nginx/          Reverse proxy + TLS configuration
│   ├── docker/         Docker Compose files (Trinity, Kortix)
│   ├── hermes/         Hermes agent configuration
│   ├── omniroute/      OmniRoute LLM router config template
│   ├── soup/           ML training + inference server
│   └── vscode/         code-server configuration
├── scripts/
│   ├── install.sh      Full VPS setup (run once)
│   ├── update.sh       Update all services
│   ├── health-check.sh Service status dashboard
│   ├── renew-certs.sh  TLS certificate renewal (cron)
│   └── backup.sh       Config backup
├── docs/
│   ├── ARCHITECTURE.md System design + data flow
│   ├── PORTS.md        Complete port reference
│   └── DEPENDENCIES.md Service dependency graph
├── .env.example        Environment variable template
├── .gitignore          Secrets + artifacts excluded
└── README.md           This file
```

## Quick Start

```bash
# 1. Clone the repo
git clone https://github.com/realaboo75/forgeos-vps.git
cd forgeos-vps

# 2. Configure environment
cp .env.example .env
# Edit .env with your values

# 3. Run installation
bash scripts/install.sh

# 4. Verify everything works
bash scripts/health-check.sh
```

## Services

| Service | URL Path | Port | Description |
|---------|----------|------|-------------|
| **ForgeOS Dashboard** | `/` | 3000 | Platform launcher & control center |
| **VS Code** | `/vscode/` | 8443 | Cloud IDE (code-server) |
| **OmniRoute** | `/omniroute/` | 20128 | Multi-provider LLM router |
| **Trinity** | `/trinity/` | 1517/8000 | Agent orchestration platform |
| **Hermes** | `/hermes/` | 13133 | AI coding agent |
| **Terminal** | `/terminal` | 8767 | Web shell access |
| **Station** | `/station/` | 8090 | Workstation dashboard |
| **Soup** | direct | 11435 | ML model serving (OpenAI API) |
| **Ollama** | direct | 11434 | Local LLM inference |

## Hardware Requirements

- **Minimum**: 2 vCPU, 12 GB RAM, 100 GB disk (ARM64 or x86_64)
- **Recommended**: 4 vCPU, 16 GB RAM, 200 GB disk
- **Swap**: 4 GB (configured by install.sh)
- **OS**: Ubuntu 22.04/24.04 LTS

## ML Pipeline

Train and serve small language models locally:

```bash
# Train SmolLM2-135M with LoRA
~/.venvs/soup/bin/python configs/soup/train_135m.py

# Or use the standalone serve script for existing models
~/.venvs/soup/bin/python configs/soup/serve_local.py
```

The serve script exposes an OpenAI-compatible API on port 11435, which OmniRoute
automatically discovers and routes to as `forgeos/smollm2-trained`.

## HTTPS / TLS

Certificates are managed by Tailscale (Let's Encrypt). They auto-renew weekly.

```bash
# Manual renewal
bash scripts/renew-certs.sh

# Add to cron for automatic renewal
echo '0 3 * * 1 bash /home/ubuntu/forgeos-vps/scripts/renew-certs.sh' | crontab -
```

## Secrets & Security

- **Never commit** `.env`, SSH keys, certificates, tokens, or passwords
- All `.gitignore` rules exclude sensitive files
- Use `.env.example` as a template — copy to `.env` and fill in values
- Services bind to `127.0.0.1` where possible (not exposed to internet)
- All external access goes through Tailscale VPN

## Maintenance

```bash
# Check all services
bash scripts/health-check.sh

# Update everything
bash scripts/update.sh

# Backup configs
bash scripts/backup.sh

# View Docker containers
docker ps --format 'table {{.Names}}\t{{.Status}}\t{{.Ports}}'

# Restart Trinity stack
docker compose -f configs/docker/docker-compose.trinity.yml restart

# Restart nginx
sudo systemctl reload nginx
```

## Architecture

See [docs/ARCHITECTURE.md](docs/ARCHITECTURE.md) for the full system design,
data flow diagrams, and security model.

See [docs/PORTS.md](docs/PORTS.md) for a complete port reference.

See [docs/DEPENDENCIES.md](docs/DEPENDENCIES.md) for service dependency graphs.

## License

Apache 2.0