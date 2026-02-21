#!/bin/bash
set -euo pipefail

INSTALL_DIR="/opt/zoraxy"
BIN_PATH="$INSTALL_DIR/zoraxy"
CONFIG_DIR="$INSTALL_DIR/config"
INIT_SCRIPT="/etc/init.d/zoraxy"
ARCH="arm64"

# Must run as root
[ "$(id -u)" -eq 0 ] || { echo "ERROR: run as root"; exit 1; }

echo "[*] Fetching latest Zoraxy release..."
LATEST=$(wget -qO- https://api.github.com/repos/tobychui/zoraxy/releases/latest | grep '"tag_name"' | cut -d'"' -f4)
echo "[*] Latest version: $LATEST"

# Check current installed version (stored on install)
CURRENT=""
[ -f "$INSTALL_DIR/version" ] && CURRENT=$(cat "$INSTALL_DIR/version")

if [ "$CURRENT" = "$LATEST" ] && [ -f "$INIT_SCRIPT" ]; then
    echo "[+] Zoraxy $LATEST is already up to date, nothing to do."
    exit 0
fi

[ -n "$CURRENT" ] && echo "[*] Updating $CURRENT -> $LATEST..." || echo "[*] Installing Zoraxy $LATEST..."

# Stop service if running
if rc-service zoraxy status &>/dev/null; then
    echo "[*] Stopping Zoraxy service..."
    rc-service zoraxy stop
fi

DOWNLOAD_URL="https://github.com/tobychui/zoraxy/releases/download/${LATEST}/zoraxy_linux_${ARCH}"

echo "[*] Downloading binary..."
mkdir -p "$INSTALL_DIR"
wget -O "${BIN_PATH}.tmp" "$DOWNLOAD_URL"
mv "${BIN_PATH}.tmp" "$BIN_PATH"
chmod +x "$BIN_PATH"
echo "$LATEST" > "$INSTALL_DIR/version"

# Preserve existing command_args across updates (e.g. -webserv, custom flags)
EXISTING_ARGS="-port=:8000"
if [ -f "$INIT_SCRIPT" ]; then
    SAVED=$(grep '^command_args=' "$INIT_SCRIPT" | cut -d'"' -f2)
    [ -n "$SAVED" ] && EXISTING_ARGS="$SAVED"
fi

# Create/update init script
echo "[*] Writing OpenRC init script..."
cat > "$INIT_SCRIPT" << EOF
#!/sbin/openrc-run

name="zoraxy"
description="Zoraxy reverse proxy"
command="/opt/zoraxy/zoraxy"
command_args="${EXISTING_ARGS}"
command_background=true
pidfile="/run/zoraxy.pid"
directory="/opt/zoraxy"
output_log="/var/log/zoraxy.log"
error_log="/var/log/zoraxy.log"

depend() {
    need net
    after networkmanager
}
EOF
chmod +x "$INIT_SCRIPT"

# Only register service if not already enabled
if ! rc-update show default 2>/dev/null | grep -q zoraxy; then
    echo "[*] Enabling Zoraxy service..."
    rc-update add zoraxy default
fi

echo "[*] Starting Zoraxy service..."
rc-service zoraxy start

echo "[+] Done! Zoraxy $LATEST ready."
echo "    Binary : $BIN_PATH"
echo "    Config : $CONFIG_DIR"
echo "    Admin panel:"
for ip in $(ip -4 addr show | awk '/inet / {print $2}' | cut -d/ -f1); do
    echo "      http://$ip:8000"
done
