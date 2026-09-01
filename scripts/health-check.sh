#!/usr/bin/env bash
# ============================================================
# ForgeOS VPS — Health Check Script
# ============================================================
set -uo pipefail

GREEN='\033[0;32m'
RED='\033[0;31m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
NC='\033[0m'

pass=0
fail=0
warn=0

check() {
    local name="$1" url="$2" expected="${3:-200}"
    local code
    code=$(curl -sk -o /dev/null -w '%{http_code}' --max-time 5 "$url" 2>/dev/null || echo "000")
    if [[ "$code" == "$expected" ]]; then
        echo -e "  ${GREEN}✓${NC} $name (HTTP $code)"
        ((pass++))
    elif [[ "$code" == "000" ]]; then
        echo -e "  ${RED}✗${NC} $name (unreachable)"
        ((fail++))
    else
        echo -e "  ${YELLOW}⚠${NC} $name (HTTP $code, expected $expected)"
        ((warn++))
    fi
}

echo -e "${CYAN}═══════════════════════════════════════${NC}"
echo -e "${CYAN}  ForgeOS VPS Health Check${NC}"
echo -e "${CYAN}═══════════════════════════════════════${NC}"
echo ""
echo "System:"
echo "  RAM:   $(free -h | awk '/Mem:/{printf \"%s / %s\", $3, $2}')"
echo "  Swap:  $(swapon --show | awk 'NR==2{printf \"%s / %s\", $3, $2}')"
echo "  Disk:  $(df -h / | awk 'NR==2{printf \"%s / %s (%s)\", $3, $2, $5}')"
echo "  Load:  $(cat /proc/loadavg | awk '{print $1, $2, $3}')"
echo ""

echo "System Services:"
for svc in docker nginx ollama tailscaled; do
    if systemctl is-active "$svc" &>/dev/null; then
        echo -e "  ${GREEN}✓${NC} $svc"
        ((pass++))
    else
        echo -e "  ${RED}✗${NC} $svc"
        ((fail++))
    fi
done
echo ""

echo "Docker Containers:"
for ctr in trinity-backend trinity-frontend trinity-redis; do
    local_status=$(docker inspect -f '{{.State.Status}}' "$ctr" 2>/dev/null || echo "not found")
    if [[ "$local_status" == "running" ]]; then
        echo -e "  ${GREEN}✓${NC} $ctr"
        ((pass++))
    else
        echo -e "  ${RED}✗${NC} $ctr ($local_status)"
        ((fail++))
    fi
done
echo ""

echo "HTTP Endpoints:"
check "ForgeOS Dashboard"  "http://127.0.0.1:3000/"
check "VS Code"            "http://127.0.0.1:8443/"    302
check "OmniRoute"          "http://127.0.0.1:20128/"
check "Hermes"             "http://127.0.0.1:13133/"
check "Trinity Backend"    "http://127.0.0.1:8000/docs"
check "Trinity Frontend"   "http://127.0.0.1:8090/"
check "Ollama"             "http://127.0.0.1:11434/"
check "code-server"        "http://127.0.0.1:8443/"    302
SOUP_CODE=$(curl -sk -o /dev/null -w '%{http_code}' --max-time 5 "http://127.0.0.1:11435/health" 2>/dev/null || echo "000")
if [[ "$SOUP_CODE" == "200" ]]; then
    echo -e "  ${GREEN}✓${NC} Soup Serve (port 11435)"
    ((pass++))
else
    echo -e "  ${YELLOW}⚠${NC} Soup Serve (not running)"
    ((warn++))
fi
echo ""

echo -e "${CYAN}───────────────────────────────────────${NC}"
echo -e "  Passed: ${GREEN}$pass${NC}  Failed: ${RED}$fail${NC}  Warnings: ${YELLOW}$warn${NC}"
echo -e "${CYAN}───────────────────────────────────────${NC}"