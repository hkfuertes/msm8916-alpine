#!/bin/sh -e
# Clean remnants of older builds
# Usage: sudo ./clear.sh

SCRIPT_DIR="$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)"
cd "$SCRIPT_DIR"

# Basic safety check (expect build.sh to exist in repo root)
if [ ! -f build.sh ]; then
    echo "Error: This script must be run from the repository root." >&2
    exit 1
fi

echo "Unmounting potential leftover mounts..."
# Unmount mnt if still mounted
if mountpoint -q mnt 2>/dev/null; then
    umount mnt || true
fi
# Unmount possible chroot bind mounts if they remain
for p in proc sys dev/pts dev run; do
    if mountpoint -q "rootfs/$p" 2>/dev/null; then
        umount "rootfs/$p" || true
    fi
done

echo "Removing build artifact directories..."
rm -rf build dist files mnt rootfs

echo "Removing generated image & archive files..."
rm -f *.raw *.bin *.tgz

echo "Clean complete."
