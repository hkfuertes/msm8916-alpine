#!/bin/bash
set -euo pipefail

INSTALL_DIR="/opt/homer"
VERSION_FILE="$INSTALL_DIR/version"

# Must run as root
[ "$(id -u)" -eq 0 ] || { echo "ERROR: run as root"; exit 1; }

echo "[*] Fetching latest Homer release..."
LATEST=$(wget -qO- https://api.github.com/repos/bastienwirtz/homer/releases/latest | grep '"tag_name"' | cut -d'"' -f4)
echo "[*] Latest version: $LATEST"

# Check current installed version
CURRENT=""
[ -f "$VERSION_FILE" ] && CURRENT=$(cat "$VERSION_FILE")

if [ "$CURRENT" = "$LATEST" ]; then
    echo "[+] Homer $LATEST is already up to date, nothing to do."
    exit 0
fi

[ -n "$CURRENT" ] && echo "[*] Updating $CURRENT -> $LATEST..." || echo "[*] Installing Homer $LATEST..."

DOWNLOAD_URL="https://github.com/bastienwirtz/homer/releases/download/${LATEST}/homer.zip"

echo "[*] Downloading Homer ${LATEST}..."
mkdir -p "$INSTALL_DIR"
wget -O "$INSTALL_DIR/homer.zip" "$DOWNLOAD_URL"

echo "[*] Extracting..."
unzip -o "$INSTALL_DIR/homer.zip" -d "$INSTALL_DIR"
rm "$INSTALL_DIR/homer.zip"

# Create default config if not present (preserve user customization on updates)
if [ ! -f "$INSTALL_DIR/assets/config.yml" ]; then
    echo "[*] Creating default config..."
    cp "$INSTALL_DIR/assets/config.yml.dist" "$INSTALL_DIR/assets/config.yml"
fi

echo "$LATEST" > "$VERSION_FILE"

echo "[+] Done! Homer $LATEST ready."
echo "    Path   : $INSTALL_DIR"
echo "    Config : $INSTALL_DIR/assets/config.yml"

# Configure Zoraxy to serve Homer's static files via -webserv flag
ZORAXY_INIT="/etc/init.d/zoraxy"
if [ -f "$ZORAXY_INIT" ]; then
    if grep -q "\-webserv" "$ZORAXY_INIT"; then
        echo "[*] Zoraxy already has -webserv flag, updating path..."
        sed -i "s|-webserv [^ ]*|-webserv $INSTALL_DIR|" "$ZORAXY_INIT"
    else
        echo "[*] Adding -webserv flag to Zoraxy init script..."
        sed -i "s|command_args=\"\(.*\)\"|command_args=\"\1 -webserv $INSTALL_DIR\"|" "$ZORAXY_INIT"
    fi

    if rc-service zoraxy status &>/dev/null; then
        echo "[*] Restarting Zoraxy..."
        rc-service zoraxy restart
    fi
    echo "[+] Zoraxy configured to serve Homer from $INSTALL_DIR"
else
    echo "[!] Zoraxy not installed yet. Run install-zoraxy.sh after this."
    echo "    It will be configured automatically on next Homer install/update."
fi
