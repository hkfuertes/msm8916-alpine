#!/bin/bash
set -euo pipefail

INSTALL_DIR="/opt/homer"
HTML_DIR="$INSTALL_DIR/html"
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
mkdir -p "$HTML_DIR"
wget -O "$INSTALL_DIR/homer.zip" "$DOWNLOAD_URL"

echo "[*] Extracting..."
unzip -o "$INSTALL_DIR/homer.zip" -d "$HTML_DIR"
rm "$INSTALL_DIR/homer.zip"

# Create default config if not present (preserve user customization on updates)
if [ ! -f "$HTML_DIR/assets/config.yml" ]; then
    echo "[*] Creating default config..."
    cp "$HTML_DIR/assets/config.yml.dist" "$HTML_DIR/assets/config.yml"
fi

echo "$LATEST" > "$VERSION_FILE"

echo "[+] Done! Homer $LATEST ready."
echo "    Path   : $HTML_DIR"
echo "    Config : $HTML_DIR/assets/config.yml"

# Configure Zoraxy to serve Homer's static files via -webroot flag
ZORAXY_INIT="/etc/init.d/zoraxy"
if [ -f "$ZORAXY_INIT" ]; then
    if grep -q "\-webroot" "$ZORAXY_INIT"; then
        echo "[*] Zoraxy already has -webroot flag, updating path..."
        sed -i "s|-webroot [^ ]*|-webroot $INSTALL_DIR|" "$ZORAXY_INIT"
    else
        echo "[*] Adding -webroot flag to Zoraxy init script..."
        sed -i "s|command_args=\"\(.*\)\"|command_args=\"\1 -webroot $INSTALL_DIR\"|" "$ZORAXY_INIT"
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
