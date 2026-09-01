#!/usr/bin/env bash
# ============================================================
# ForgeOS VPS — Certificate Renewal (Tailscale)
# Run via cron: 0 3 * * 1 bash /path/to/renew-certs.sh
# ============================================================
set -euo pipefail

DOMAIN=$(tailscale status --json 2>/dev/null | jq -r '.Self.DNSName | rtrim(".")')
if [[ -z "$DOMAIN" ]]; then
    echo "ERROR: Tailscale not connected"
    exit 1
fi

sudo tailscale cert "$DOMAIN" \
    --cert-file /etc/nginx/ssl/tailscale.crt \
    --key-file /etc/nginx/ssl/tailscale.key

sudo systemctl reload nginx
echo "[$(date)] TLS certificate renewed for $DOMAIN"