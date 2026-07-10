#!/bin/bash
# Fast validation of the kernel build environment.
# Fetches the pmaports APKBUILD (v26.06) to verify pkgver/tag, checks URL reachability.
# Does NOT compile anything. Exit 0 = all checks pass; Exit 1 = one or more failures.

set -euo pipefail

ERRORS=0

ok()   { echo "[ OK ] $1"; }
fail() { echo "[FAIL] $1"; ERRORS=$((ERRORS + 1)); }
info() { echo "[    ] $1"; }

# --- Tool checks ---
for tool in make wget bc flex bison; do
    command -v "$tool" &>/dev/null && ok "$tool" || fail "$tool not found"
done

# libelf: needed by modules_prepare for BTF / DWARF
if pkg-config --exists libelf 2>/dev/null || find /usr -name 'libelf.h' 2>/dev/null | grep -q .; then
    ok "libelf headers"
else
    fail "libelf-dev not found (apt install libelf-dev)"
fi

# Cross-compiler
if [ "$(uname -m)" = "aarch64" ]; then
    command -v gcc &>/dev/null && ok "gcc (native arm64)" || fail "gcc not found"
else
    command -v aarch64-linux-gnu-gcc &>/dev/null \
        && ok "aarch64-linux-gnu-gcc (cross)" \
        || fail "aarch64-linux-gnu-gcc not found (apt install gcc-aarch64-linux-gnu)"
fi

# --- APKBUILD fetch + version/tag verification ---
info "Fetching pmaports v26.06 APKBUILD to verify pkgver and _tag ..."
APKBUILD_URL='https://gitlab.postmarketos.org/postmarketOS/pmaports/-/raw/v26.06/device/community/linux-postmarketos-qcom-msm8916/APKBUILD'
APKBUILD_TMP="$(mktemp /tmp/validate-apkbuild.XXXXXX)"
if wget -q -O "$APKBUILD_TMP" "$APKBUILD_URL" 2>/dev/null; then
    ok "APKBUILD URL reachable (pmaports v26.06)"
    _pkgver="$(grep '^pkgver=' "$APKBUILD_TMP" | cut -d= -f2 | tr -d '[:space:]')"
    if [ "$_pkgver" = "6.12.1" ]; then
        ok "APKBUILD pkgver=${_pkgver}"
    else
        fail "APKBUILD pkgver=${_pkgver} (expected 6.12.1)"
    fi
    # Verify source line references the expected tag
    _expected_tag="v${_pkgver}-msm8916"
    if grep -q "${_expected_tag}" "$APKBUILD_TMP"; then
        ok "APKBUILD source references tag ${_expected_tag}"
    else
        fail "APKBUILD source does not reference expected tag ${_expected_tag}"
    fi
else
    fail "APKBUILD URL not reachable: $APKBUILD_URL"
fi
rm -f "$APKBUILD_TMP"

# --- URL reachability ---
info "Checking upstream URLs (requires network) ..."
wget -q --spider 'https://github.com/msm8916-mainline/linux/archive/v6.12.1-msm8916.tar.gz' 2>/dev/null \
    && ok "kernel source URL reachable (v6.12.1-msm8916)" \
    || fail "kernel source URL not reachable"

wget -q --spider 'https://gitlab.postmarketos.org/postmarketOS/pmaports/-/raw/v26.06/device/community/linux-postmarketos-qcom-msm8916/config-postmarketos-qcom-msm8916.aarch64' 2>/dev/null \
    && ok "pmaports config URL reachable (v26.06)" \
    || fail "pmaports config URL not reachable (v26.06)"

# --- Config fragment: USB serial printer drivers (issue-003) ---
REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
FRAGMENT="$REPO_ROOT/kernel/usb-serial-printer.config"
USB_SERIAL_SYMBOLS="CONFIG_USB_SERIAL CONFIG_USB_SERIAL_CH341 CONFIG_USB_ACM CONFIG_USB_SERIAL_FTDI_SIO CONFIG_USB_SERIAL_PL2303"
if [ -f "$FRAGMENT" ]; then
    ok "config fragment exists (kernel/usb-serial-printer.config)"
    for sym in $USB_SERIAL_SYMBOLS; do
        grep -q "^${sym}=" "$FRAGMENT" && ok "fragment: ${sym}" || fail "fragment missing: ${sym}"
    done
else
    fail "config fragment missing: kernel/usb-serial-printer.config"
fi

# --- Build script for USB modules (issue-004) ---
if [ -f "$REPO_ROOT/scripts/build-usb-modules.sh" ]; then
    ok "build-usb-modules.sh present"
else
    fail "scripts/build-usb-modules.sh missing"
fi

# --- Optional: check if setup was already run ---
KSRC="$REPO_ROOT/kernel-build/linux-6.12.1-msm8916"
if [ -f "$KSRC/scripts/mod/modpost" ]; then
    ok "modules_prepare already done ($KSRC)"
    # Verify USB serial symbols landed in the prepared .config
    if [ -f "$KSRC/.config" ]; then
        for sym in $USB_SERIAL_SYMBOLS; do
            grep -q "^${sym}=m" "$KSRC/.config" && ok ".config: ${sym}=m" || fail ".config: ${sym} not =m (re-run setup-kernel-build.sh)"
        done
    fi
else
    info "kernel-build not set up yet — run: sudo bash scripts/setup-kernel-build.sh"
fi

# --- Optional: check if modules were already built ---
ARTIFACT_DIR="$REPO_ROOT/modules/octoprint-usb-serial/6.12.1-msm8916"
if [ -d "$ARTIFACT_DIR" ] && ls "$ARTIFACT_DIR"/*.ko 2>/dev/null | grep -q .; then
    ok "USB modules already built ($(ls "$ARTIFACT_DIR"/*.ko | wc -l | tr -d ' ') .ko files in modules/octoprint-usb-serial/)"
else
    info "USB modules not built yet — run: sudo bash scripts/build-usb-modules.sh"
fi

echo ""
if [ "$ERRORS" -eq 0 ]; then
    echo "Environment OK."
    exit 0
else
    echo "$ERRORS check(s) failed."
    exit 1
fi
