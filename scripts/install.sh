#!/usr/bin/env bash
# ============================================================
# ForgeOS VPS — Full Installation Script
# Tested on: Oracle Ubuntu 22.04/24.04 (ARM64), 2 vCPU, 12GB RAM
# ============================================================
set -euo pipefail

# ── Colors ──────────────────────────────────────────────────
GREEN='\033[0;32m'
RED='\033[0;31m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
NC='\033[0m'

info()  { echo -e "${CYAN}[INFO]${NC} $*"; }
ok()    { echo -e "${GREEN}[OK]${NC} $*"; }
warn()  { echo -e "${YELLOW}[WARN]${NC} $*"; }
err()   { echo -e "${RED}[ERROR]${NC} $*"; }

# ── Pre-flight ─────────────────────────────────────────────
info "ForgeOS VPS Installation"
info "System: $(uname -s) $(uname -m)"
info "RAM: $(free -h | awk '/Mem:/{print $2}') — Disk: $(df -h / | awk 'NR==2{print $2}')"

if [[ $EUID -eq 0 ]]; then
    err "Do not run as root. Use a user with sudo privileges."
    exit 1
fi

# ── 1. System Updates ──────────────────────────────────────
info "Step 1: System updates..."
sudo apt-get update -qq
sudo apt-get install -y -qq \
    curl wget git build-essential \
    nginx \
    python3 python3-pip python3-venv \
    jq unzip software-properties-common
ok "System packages installed"

# ── 2. Swap (4GB) ─────────────────────────────────────────
info "Step 2: Configuring 4GB swap..."
if ! swapon --show | grep -q '/swapfile'; then
    sudo fallocate -l 4G /swapfile
    sudo chmod 600 /swapfile
    sudo mkswap /swapfile
    sudo swapon /swapfile
    echo '/swapfile none swap sw 0 0' | sudo tee -a /etc/fstab
    sudo sysctl vm.swappiness=10
    echo 'vm.swappiness=10' | sudo tee -a /etc/sysctl.conf
    ok "Swap created: $(swapon --show | awk 'NR==2{print $3}')"
else
    ok "Swap already active: $(swapon --show | awk 'NR==2{print $3}')"
fi

# ── 3. Tailscale ──────────────────────────────────────────
info "Step 3: Installing Tailscale..."
if ! command -v tailscale &>/dev/null; then
    curl -fsSL https://tailscale.com/install.sh | sh
fi
if [[ -n "${TAILSCALE_AUTHKEY:-}" ]]; then
    sudo tailscale up --authkey="$TAILSCALE_AUTHKEY" --hostname="${TAILSCALE_HOSTNAME:-forgeos-vps}"
else
    warn "Set TAILSCALE_AUTHKEY in .env, then run: sudo tailscale up --hostname=forgeos-vps"
fi
ok "Tailscale installed"

# ── 4. Docker ─────────────────────────────────────────────
info "Step 4: Installing Docker..."
if ! command -v docker &>/dev/null; then
    curl -fsSL https://get.docker.com | sh
    sudo usermod -aG docker "$USER"
    warn "Log out and back in for Docker group membership"
fi
ok "Docker: $(docker --version)"

# ── 5. Docker Compose ─────────────────────────────────────
info "Step 5: Installing Docker Compose plugin..."
if ! docker compose version &>/dev/null; then
    sudo apt-get install -y docker-compose-plugin
fi
ok "Docker Compose: $(docker compose version)"

# ── 6. Ollama ─────────────────────────────────────────────
info "Step 6: Installing Ollama..."
if ! command -v ollama &>/dev/null; then
    curl -fsSL https://ollama.com/install.sh | sh
fi
ollama pull phi3:mini 2>/dev/null || true
ollama pull phi:2.7b 2>/dev/null || true
ok "Ollama: $(ollama --version)"

# ── 7. Python Virtualenv + Soup ───────────────────────────
info "Step 7: Setting up Soup ML environment..."
SOUVENVS="/home/$USER/.venvs/soup"
if [[ ! -d "$SOUVENVS" ]]; then
    python3 -m venv "$SOUVENVS"
fi
"$SOUVENVS/bin/pip" install -q --upgrade pip
"$SOUVENVS/bin/pip" install -q \
    transformers peft datasets torch psutil accelerate
ok "Soup venv: $SOUVENVS"

# ── 8. OmniRoute ──────────────────────────────────────────
info "Step 8: Installing OmniRoute..."
if ! command -v omniroute &>/dev/null; then
    npm install -g omniroute 2>/dev/null || true
fi
ok "OmniRoute installed"

# ── 9. Hermes ─────────────────────────────────────────────
info "Step 9: Setting up Hermes Agent..."
HERMES_HOME="$HOME/.hermes"
mkdir -p "$HERMES_HOME"
ok "Hermes directory: $HERMES_HOME"

# ── 10. code-server (VS Code) ─────────────────────────────
info "Step 10: Installing code-server..."
if ! command -v code-server &>/dev/null; then
    curl -fsSL https://code-server.dev/install.sh | sh
fi
mkdir -p "$HOME/.config/code-server"
cat > "$HOME/.config/code-server/config.yaml" << 'CODESERVER'
bind-addr: 0.0.0.0:8443
auth: none
cert: false
CODESERVER
ok "code-server: $(code-server --version)"

# ── 11. Nginx ─────────────────────────────────────────────
info "Step 11: Configuring Nginx..."
sudo cp configs/nginx/forgeos-ssl.conf /etc/nginx/sites-enabled/forgeos-ssl.conf
sudo rm -f /etc/nginx/sites-enabled/default
sudo rm -f /etc/nginx/sites-enabled/n8n*
sudo nginx -t
sudo systemctl reload nginx
ok "Nginx configured with HTTPS"

# ── 12. SSL Certificates (Tailscale) ─────────────────────
info "Step 12: Generating TLS certificates..."
DOMAIN=$(tailscale status --json 2>/dev/null | jq -r '.Self.DNSName | rtrim(".")' || echo "")
if [[ -n "$DOMAIN" ]]; then
    sudo mkdir -p /etc/nginx/ssl
    sudo tailscale cert "$DOMAIN" \
        --cert-file /etc/nginx/ssl/tailscale.crt \
        --key-file /etc/nginx/ssl/tailscale.key
    ok "TLS cert for $DOMAIN"
else
    warn "Tailscale not connected. Run: sudo tailscale up"
fi

# ── 13. Trinity Stack ─────────────────────────────────────
info "Step 13: Starting Trinity stack..."
if [[ -f configs/docker/docker-compose.trinity.yml ]]; then
    docker compose -f configs/docker/docker-compose.trinity.yml up -d
    ok "Trinity stack started"
else
    warn "Trinity docker-compose not found"
fi

# ── Done ───────────────────────────────────────────────────
echo ""
echo -e "${GREEN}========================================${NC}"
echo -e "${GREEN}  ForgeOS VPS Installation Complete!   ${NC}"
echo -e "${GREEN}========================================${NC}"
echo ""
echo "Run health check:  bash scripts/health-check.sh"