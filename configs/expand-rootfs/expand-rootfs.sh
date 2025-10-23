#!/bin/sh
# Expand rootfs filesystem on first boot
set -e

ROOT_DEV=$(awk '$2 == "/" {print $1}' /proc/mounts | head -1)
echo "[*] Expanding filesystem on $ROOT_DEV..."

# Check filesystem
e2fsck -fy "$ROOT_DEV" || true

# Resize filesystem to fill partition
if resize2fs "$ROOT_DEV"; then
    echo "[+] Filesystem expanded successfully!"
    df -h /
    touch /var/lib/expand-rootfs.done
else
    echo "ERROR: Failed to resize filesystem"
    exit 1
fi
