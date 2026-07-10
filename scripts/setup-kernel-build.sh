#!/bin/bash
# Setup kernel source tree for out-of-tree module builds against msm8916 pmaports kernel.
# Pins pmaports v26.06; derives kernel version/tag from the official APKBUILD.
# Run inside the builder VM (make builder) or any arm64/amd64 Linux box with
# the required cross-build deps installed (see build-deps.sh).
#
# Usage: sudo bash scripts/setup-kernel-build.sh
#   Optional: copy /proc/config.gz from the device to kernel-build/device.config.gz
#   before running; the script will prefer that over the pmaports default config.

set -euo pipefail

FLAVOR="postmarketos-qcom-msm8916"
PMAPORTS_REF="v26.06"
PMAPORTS_BASE="https://gitlab.postmarketos.org/postmarketOS/pmaports/-/raw/${PMAPORTS_REF}/device/community/linux-${FLAVOR}"
APKBUILD_URL="${PMAPORTS_BASE}/APKBUILD"
CONFIG_URL="${PMAPORTS_BASE}/config-${FLAVOR}.aarch64"
REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
BUILD_DIR="$REPO_ROOT/kernel-build"

mkdir -p "$BUILD_DIR"

# --- 0. Fetch APKBUILD and derive version/tag (single source of truth) ---
echo "[+] Fetching APKBUILD from pmaports ${PMAPORTS_REF} ..."
wget -q -O "$BUILD_DIR/APKBUILD" "$APKBUILD_URL"
# ponytail: parse with grep/sed; APKBUILD is shell so sourcing it is risky
KVER="$(grep '^pkgver=' "$BUILD_DIR/APKBUILD" | cut -d= -f2 | tr -d '[:space:]')"
if [ "$KVER" != "6.12.1" ]; then
    echo "[FAIL] pmaports ${PMAPORTS_REF} APKBUILD reports pkgver=${KVER}, expected 6.12.1" >&2
    exit 1
fi
# _tag is defined as v${pkgver}-msm8916 in APKBUILD
KTAG="v${KVER}-msm8916"
KSRC_DIR="linux-${KVER}-msm8916"
KERNEL_URL="https://github.com/msm8916-mainline/linux/archive/${KTAG}.tar.gz"
echo "[+] APKBUILD pkgver=${KVER}  _tag=${KTAG}"

# Detect cross-compile prefix
if [ "$(uname -m)" = "aarch64" ]; then
    CROSS_COMPILE=""
else
    CROSS_COMPILE="aarch64-linux-gnu-"
fi

echo "[msm8916-kern] BUILD_DIR : $BUILD_DIR"
echo "[msm8916-kern] kernel tag: $KTAG"
echo "[msm8916-kern] pmaports  : ${PMAPORTS_REF}"
echo "[msm8916-kern] CROSS     : ${CROSS_COMPILE:-<native arm64>}"

cd "$BUILD_DIR"

# --- 1. Kernel source ---
if [ ! -d "$KSRC_DIR" ]; then
    echo "[+] Downloading kernel source ${KTAG} ..."
    wget -q --show-progress -O "${KTAG}.tar.gz" "$KERNEL_URL"
    tar xzf "${KTAG}.tar.gz"
    rm "${KTAG}.tar.gz"
    echo "[+] Extracted → $BUILD_DIR/$KSRC_DIR"
else
    echo "[=] Kernel source already present, skipping download."
fi

# --- 2. Kernel config ---
# Prefer a config snapshot copied from the running device (/proc/config.gz).
if [ -f "device.config.gz" ]; then
    echo "[+] Using device config (device.config.gz)"
    zcat device.config.gz > "$KSRC_DIR/.config"
else
    echo "[+] Downloading pmaports config for $FLAVOR ..."
    wget -q -O "config-${FLAVOR}.aarch64" "$CONFIG_URL"
    cp "config-${FLAVOR}.aarch64" "$KSRC_DIR/.config"
    echo "    (tip: copy /proc/config.gz from the device to kernel-build/device.config.gz"
    echo "     and re-run for an exact match with the running kernel)"
fi

# --- 2b. Apply local config fragment (USB serial printer drivers, issue-003) ---
FRAGMENT="$REPO_ROOT/kernel/usb-serial-printer.config"
if [ -f "$FRAGMENT" ]; then
    echo "[+] Applying config fragment: kernel/usb-serial-printer.config"
    # ponytail: append wins over earlier 'not set' lines; olddefconfig finalises deps
    cat "$FRAGMENT" >> "$KSRC_DIR/.config"
else
    echo "[WARN] Config fragment not found, skipping: $FRAGMENT"
fi

# --- 3. modules_prepare (no full kernel compile) ---
cd "$KSRC_DIR"
echo "[+] Running make olddefconfig + modules_prepare ..."

make ARCH=arm64 CROSS_COMPILE="$CROSS_COMPILE" olddefconfig
# ponytail: modules_prepare builds only what out-of-tree modules need (scripts, headers, Module.symvers)
make ARCH=arm64 CROSS_COMPILE="$CROSS_COMPILE" modules_prepare

echo ""
echo "[msm8916-kern] Done. Build environment ready at:"
echo "  $BUILD_DIR/$KSRC_DIR"
echo ""
echo "  Build an out-of-tree module with:"
echo "    make -C $BUILD_DIR/$KSRC_DIR M=\$(pwd) ARCH=arm64 CROSS_COMPILE=$CROSS_COMPILE modules"
