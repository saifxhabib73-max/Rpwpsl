#!/bin/bash

# ============================================
# Windows RDP via Tailscale - Start Script
# ============================================

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# ============================================
# Check env vars
# ============================================
echo -e "${BLUE}[INFO] Checking environment variables...${NC}"

if [ -z "$TS_AUTHKEY" ]; then
    echo -e "${RED}[ERROR] TS_AUTHKEY is not set.${NC}"
    echo -e "${YELLOW}Usage: TS_AUTHKEY=tskey-auth-xxx RDP_PASSWORD=YourPass ./start.sh${NC}"
    exit 1
fi

if [ -z "$RDP_PASSWORD" ]; then
    echo -e "${RED}[ERROR] RDP_PASSWORD is not set.${NC}"
    echo -e "${YELLOW}Usage: TS_AUTHKEY=tskey-auth-xxx RDP_PASSWORD=YourPass ./start.sh${NC}"
    exit 1
fi

echo -e "${GREEN}[OK] Environment variables loaded.${NC}"

# ============================================
# Install Tailscale
# ============================================
echo -e "${BLUE}[INFO] Checking Tailscale...${NC}"

if command -v tailscale &> /dev/null; then
    echo -e "${GREEN}[OK] Tailscale already installed.${NC}"
else
    echo -e "${YELLOW}[INFO] Installing Tailscale...${NC}"
    curl -fsSL https://tailscale.com/install.sh | sh
    if [ $? -ne 0 ]; then
        echo -e "${RED}[ERROR] Tailscale installation failed.${NC}"
        exit 1
    fi
    echo -e "${GREEN}[OK] Tailscale installed.${NC}"
fi

# ============================================
# Start Tailscale Service
# ============================================
echo -e "${BLUE}[INFO] Starting Tailscale service...${NC}"

if command -v systemctl &> /dev/null; then
    sudo systemctl start tailscaled 2>/dev/null || true
else
    sudo tailscaled &
    sleep 3
fi

echo -e "${GREEN}[OK] Tailscale service started.${NC}"

# ============================================
# Connect to Tailscale
# ============================================
echo -e "${BLUE}[INFO] Connecting to Tailscale...${NC}"

sudo tailscale up \
    --authkey="$TS_AUTHKEY" \
    --hostname="python-windows-rdp" \
    --accept-routes

if [ $? -ne 0 ]; then
    echo -e "${RED}[ERROR] Failed to connect to Tailscale.${NC}"
    exit 1
fi

echo -e "${GREEN}[OK] Connected to Tailscale.${NC}"

# ============================================
# Enable RDP (via PowerShell on Windows)
# ============================================
echo -e "${BLUE}[INFO] Enabling RDP...${NC}"

powershell.exe -NoProfile -ExecutionPolicy Bypass -Command "
    Set-ItemProperty -Path 'HKLM:\System\CurrentControlSet\Control\Terminal Server' \
        -Name 'fDenyTSConnections' -Value 0;
    Enable-NetFirewallRule -DisplayGroup 'Remote Desktop';
    Set-ItemProperty -Path 'HKLM:\System\CurrentControlSet\Control\Terminal Server\WinStations\RDP-Tcp' \
        -Name 'UserAuthentication' -Value 0;
    Write-Host 'RDP Enabled'
"

if [ $? -ne 0 ]; then
    echo -e "${RED}[ERROR] Failed to enable RDP.${NC}"
    exit 1
fi

echo -e "${GREEN}[OK] RDP Enabled.${NC}"

# ============================================
# Set RDP Password
# ============================================
echo -e "${BLUE}[INFO] Setting RDP password...${NC}"

powershell.exe -NoProfile -ExecutionPolicy Bypass -Command "
    \$Password = ConvertTo-SecureString '$RDP_PASSWORD' -AsPlainText -Force;
    Set-LocalUser -Name 'runneradmin' -Password \$Password;
    Add-LocalGroupMember -Group 'Remote Desktop Users' -Member 'runneradmin' -ErrorAction SilentlyContinue;
    Write-Host 'Password Set'
"

if [ $? -ne 0 ]; then
    echo -e "${RED}[ERROR] Failed to set RDP password.${NC}"
    exit 1
fi

echo -e "${GREEN}[OK] RDP password set.${NC}"

# ============================================
# Get Tailscale IP
# ============================================
echo -e "${BLUE}[INFO] Getting Tailscale IP...${NC}"

TAILSCALE_IP=$(tailscale ip -4 2>/dev/null)

if [ -z "$TAILSCALE_IP" ]; then
    echo -e "${RED}[ERROR] Could not get Tailscale IP.${NC}"
    exit 1
fi

# ============================================
# Show Connection Details
# ============================================
echo ""
echo -e "${GREEN}========================================${NC}"
echo -e "${GREEN}         RDP CONNECTION DETAILS         ${NC}"
echo -e "${GREEN}========================================${NC}"
echo -e "${YELLOW}Host     : ${TAILSCALE_IP}${NC}"
echo -e "${YELLOW}Username : runneradmin${NC}"
echo -e "${YELLOW}Password : ${RDP_PASSWORD}${NC}"
echo -e "${GREEN}========================================${NC}"
echo ""

# ============================================
# Keep Alive
# ============================================
echo -e "${BLUE}[INFO] Keeping session alive...${NC}"

SECONDS_LEFT=21600  # 6 hours

while [ $SECONDS_LEFT -gt 0 ]; do
    HOURS=$((SECONDS_LEFT / 3600))
    MINUTES=$(( (SECONDS_LEFT % 3600) / 60 ))
    echo -e "${BLUE}[INFO] Time remaining: ${HOURS}h ${MINUTES}m | Tailscale IP: ${TAILSCALE_IP}${NC}"
    sleep 300
    SECONDS_LEFT=$((SECONDS_LEFT - 300))
done

echo -e "${RED}[INFO] Session ended.${NC}"
