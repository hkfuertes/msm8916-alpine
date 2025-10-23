#!/bin/sh -e
# Detectar el dispositivo raíz y el padre del bloque
ROOT_DEV="$(findmnt -no SOURCE /)"
DISK="$(lsblk -no PKNAME "$ROOT_DEV")"
PARTNUM="$(echo "$ROOT_DEV" | sed -E 's|.*[^0-9]([0-9]+)$|\1|')"

# Crecer la partición al final del disco
growpart "/dev/$DISK" "$PARTNUM"
partprobe "/dev/$DISK" || true
udevadm settle || true

# Redimensionar el sistema de archivos según tipo
FSTYPE="$(findmnt -no FSTYPE /)"
case "$FSTYPE" in
  ext4) resize2fs "$ROOT_DEV" ;;
  f2fs) resize.f2fs "$ROOT_DEV" ;;
  btrfs) btrfs filesystem resize max / ;;
  xfs) xfs_growfs / ;;
  *) echo "FS no soportado: $FSTYPE" >&2; exit 1 ;;
esac

# Marcar como hecho
touch /var/lib/expand-rootfs.done
