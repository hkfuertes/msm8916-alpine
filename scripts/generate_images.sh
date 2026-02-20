#!/bin/bash
set -euo pipefail

# Paths
WORKDIR="$(pwd)"
OUT_DIR="${1:-"$WORKDIR/files"}"
STAGING="$(mktemp -d)"
ROOTFS_TAR="$OUT_DIR/rootfs.tgz"
BOOT_RAW="$STAGING/boot.raw"
ROOT_RAW="$STAGING/rootfs.raw"

# Cleanup on exit
trap 'rm -rf "$STAGING"' EXIT INT TERM

# Sizes (adjustable)
BOOT_SIZE_MIB="${BOOT_SIZE_MIB:=64}"
ROOT_SIZE_MIB="${ROOT_SIZE_MIB:=1536}"

# Requirements
command -v img2simg >/dev/null || { echo "Falta img2simg"; exit 1; }
[ -d "$OUT_DIR" ] || { echo "No existe directorio: $OUT_DIR"; exit 1; }
[ -f "$ROOTFS_TAR" ] || { echo "No existe $ROOTFS_TAR"; exit 1; }

echo "[*] Output directory: $OUT_DIR"
echo "[*] Temporary staging: $STAGING"
echo "[*] Rootfs source: $ROOTFS_TAR"

# Prep
mkdir -p "$STAGING/mnt"

# Create boot image (ext2)
echo "[*] Creating boot image ($BOOT_SIZE_MIB MiB)..."
truncate -s "$((BOOT_SIZE_MIB * 1024 * 1024))" "$BOOT_RAW"
mkfs.ext2 -F "$BOOT_RAW" >/dev/null 2>&1
mount -o loop "$BOOT_RAW" "$STAGING/mnt"

echo "[*] Extracting boot files..."
# CRÍTICO: strip-components=2 para dejar archivos en raíz de boot partition
tar xf "$ROOTFS_TAR" -C "$STAGING/mnt" \
    ./boot \
    --exclude='./boot/linux.efi' \
    --strip-components=2 \
    2>/dev/null || true

echo "[*] Boot partition contents:"
ls -lhR "$STAGING/mnt/" | head -30 || true

umount "$STAGING/mnt"

# Create rootfs image (ext4)
echo "[*] Creating rootfs image ($ROOT_SIZE_MIB MiB)..."
truncate -s "$((ROOT_SIZE_MIB * 1024 * 1024))" "$ROOT_RAW"
mkfs.ext4 -F "$ROOT_RAW" >/dev/null 2>&1
mount -o loop "$ROOT_RAW" "$STAGING/mnt"

echo "[*] Extracting rootfs files..."
tar xpf "$ROOTFS_TAR" -C "$STAGING/mnt" \
    --exclude='./boot/*' \
    --exclude='./root/*' \
    --exclude='./dev/*' 2>/dev/null || true

umount "$STAGING/mnt"

# Convert to sparse Android images
echo "[*] Converting to sparse images..."
img2simg "$BOOT_RAW" "$OUT_DIR/boot.bin"
img2simg "$ROOT_RAW" "$OUT_DIR/rootfs.bin"

echo "[+] Images created successfully:"
echo "    - $OUT_DIR/boot.bin ($(du -h "$OUT_DIR/boot.bin" | cut -f1))"
echo "    - $OUT_DIR/rootfs.bin ($(du -h "$OUT_DIR/rootfs.bin" | cut -f1))"
