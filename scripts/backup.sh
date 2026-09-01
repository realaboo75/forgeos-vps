#!/usr/bin/env bash
# ============================================================
# ForgeOS VPS — Backup Script (config only, no secrets)
# ============================================================
set -euo pipefail

BACKUP_DIR="${BACKUP_DIR:-/home/ubuntu/backups}"
TIMESTAMP=$(date +%Y%m%d_%H%M%S)
BACKUP_FILE="$BACKUP_DIR/forgeos-config-$TIMESTAMP.tar.gz"

mkdir -p "$BACKUP_DIR"

tar czf "$BACKUP_FILE" \
    --exclude='*.db' \
    --exclude='*.sqlite*' \
    --exclude='*.log' \
    --exclude='*.pem' \
    --exclude='*.key' \
    --exclude='*.crt' \
    --exclude='node_modules' \
    --exclude='__pycache__' \
    --exclude='*.safetensors' \
    --exclude='*.bin' \
    --exclude='*.pt' \
    --exclude='output/' \
    --exclude='models/' \
    --exclude='.env' \
    /etc/nginx/sites-enabled/forgeos-ssl.conf \
    /etc/nginx/nginx.conf \
    "$HOME/.config/code-server/" \
    "$HOME/.hermes/config.yaml" \
    "$HOME/.omniroute/.env" \
    2>/dev/null || true

echo "Backup saved: $BACKUP_FILE ($(du -h "$BACKUP_FILE" | cut -f1))"