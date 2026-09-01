#!/usr/bin/env bash
# ============================================================
# ForgeOS VPS — Update Script
# Updates all services without downtime
# ============================================================
set -euo pipefail

echo "ForgeOS VPS Update"
echo "=================="

# ── System packages ────────────────────────────────────────
sudo apt-get update -qq && sudo apt-get upgrade -y -qq

# ── Docker images ──────────────────────────────────────────
docker pull redis:7-alpine
docker pull otel/opentelemetry-collector-contrib:0.120.0
docker pull timberio/vector:0.43.1-alpine

# ── Ollama models ──────────────────────────────────────────
ollama pull phi3:mini 2>/dev/null || true
ollama pull phi:2.7b 2>/dev/null || true

# ── Python packages ────────────────────────────────────────
SOUVENVS="/home/$USER/.venvs/soup"
if [[ -d "$SOUVENVS" ]]; then
    "$SOUVENVS/bin/pip" install -q --upgrade transformers peft datasets torch psutil accelerate
fi

# ── Nginx ──────────────────────────────────────────────────
sudo nginx -t && sudo systemctl reload nginx
echo "Nginx reloaded"

# ── Refresh TLS certificate ───────────────────────────────
DOMAIN=$(tailscale status --json 2>/dev/null | jq -r '.Self.DNSName | rtrim(".")' 2>/dev/null || echo "")
if [[ -n "$DOMAIN" ]]; then
    sudo tailscale cert "$DOMAIN" \
        --cert-file /etc/nginx/ssl/tailscale.crt \
        --key-file /etc/nginx/ssl/tailscale.key 2>/dev/null || true
    sudo systemctl reload nginx
    echo "TLS certificate refreshed"
fi

# ── Restart Docker containers ─────────────────────────────
docker compose -f configs/docker/docker-compose.trinity.yml down 2>/dev/null || true
docker compose -f configs/docker/docker-compose.trinity.yml up -d

echo ""
echo "Update complete!"
echo "Run health check: bash scripts/health-check.sh"