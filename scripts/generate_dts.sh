#!/bin/bash
set -euo pipefail

# Compiles DTS files to DTB:
#   1. Sparse-checkouts kernel DTS (cached in .kernel-dts/)
#   2. Compiles known upstream MSM8916 DTS files
#   3. Compiles any user-provided DTS in dts/
# Usage: ./scripts/generate_dts.sh <out_dir>

WORKDIR="$(pwd)"
OUT_DIR="${1:-"$WORKDIR/files"}"
DTB_OUT="$OUT_DIR/dtbs"
KERNEL_CACHE="$WORKDIR/.kernel-dts"
KERNEL_REPO="https://github.com/torvalds/linux.git"

# Upstream DTS files to compile (relative to arch/arm64/boot/dts/qcom/)
UPSTREAM_DTS=(
    "msm8916-yiming-uz801v3.dts"
    "msm8916-thwc-uf896.dts"
    "msm8916-thwc-ufi001c.dts"
)

command -v dtc  >/dev/null || { echo "ERROR: dtc not found. Run install_dependencies.sh"; exit 1; }
command -v cpp  >/dev/null || { echo "ERROR: cpp not found. Run install_dependencies.sh"; exit 1; }
command -v git  >/dev/null || { echo "ERROR: git not found. Run install_dependencies.sh"; exit 1; }

mkdir -p "$DTB_OUT"

# ---------------------------------------------------------------------------
# 1. Sparse-checkout kernel DTS tree (cached)
# ---------------------------------------------------------------------------
if [ ! -d "$KERNEL_CACHE/.git" ]; then
    echo "[*] Cloning kernel DTS tree (sparse, this may take a moment)..."
    git clone --sparse --depth=1 "$KERNEL_REPO" "$KERNEL_CACHE"
    git -C "$KERNEL_CACHE" sparse-checkout set \
        arch/arm64/boot/dts/qcom \
        include/dt-bindings \
        include/uapi/linux
    echo "[+] Kernel DTS tree cached in $KERNEL_CACHE"
else
    echo "[*] Using cached kernel DTS tree ($KERNEL_CACHE)"
fi

DTS_QCOM="$KERNEL_CACHE/arch/arm64/boot/dts/qcom"
INC="$KERNEL_CACHE/include"

# ---------------------------------------------------------------------------
# 2. Compile function
# ---------------------------------------------------------------------------
compile_dts() {
    local src="$1"
    local name
    name="$(basename "$src" .dts)"
    local out="$DTB_OUT/${name}.dtb"
    echo "[*] Compiling $(basename "$src") -> $(basename "$out")"
    cpp -nostdinc -undef -x assembler-with-cpp \
        -I "$INC" -I "$DTS_QCOM" \
        "$src" | dtc -I dts -O dtb -@ -o "$out"
}

# ---------------------------------------------------------------------------
# 3. Compile upstream DTS files
# ---------------------------------------------------------------------------
echo "[*] Compiling upstream DTS files..."
for dts in "${UPSTREAM_DTS[@]}"; do
    src="$DTS_QCOM/$dts"
    if [ -f "$src" ]; then
        compile_dts "$src"
    else
        echo "[!] Skipping $dts — not found in kernel tree"
    fi
done

# ---------------------------------------------------------------------------
# 4. Compile user-provided DTS files from dts/
# ---------------------------------------------------------------------------
shopt -s nullglob
user_dts=("$WORKDIR/dts/"*.dts)
shopt -u nullglob

if [ ${#user_dts[@]} -gt 0 ]; then
    echo "[*] Compiling user DTS files..."
    for src in "${user_dts[@]}"; do
        compile_dts "$src"
    done
else
    echo "[*] No user DTS files in dts/ — skipping"
fi

echo "[+] DTBs compiled to $DTB_OUT"
ls -lh "$DTB_OUT"/*.dtb 2>/dev/null || echo "    (none)"
