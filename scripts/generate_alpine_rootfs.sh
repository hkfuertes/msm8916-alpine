#!/bin/sh -e

. ./variables.env

# Configuration
WORKDIR="$(pwd)"
OUT_DIR="${1:-"$WORKDIR/files"}"
STAGING="$(mktemp -d)"
CHROOT="$STAGING/rootfs"

HOST_NAME="${HOST_NAME:=uz801a}"
RELEASE="${RELEASE:=v3.20}"
PMOS_RELEASE="${PMOS_RELEASE:=v24.12}"
MIRROR="${MIRROR:=http://dl-cdn.alpinelinux.org/alpine}"
PMOS_MIRROR="${PMOS_MIRROR:=http://mirror.postmarketos.org/postmarketos}"

USERNAME="${USERNAME:=user}"
PASSWORD="${PASSWORD:=1}"

# Cleanup on exit
trap 'rm -rf "$STAGING"' EXIT INT TERM

# Validations
[ -d "$OUT_DIR" ] || { echo "No existe directorio de salida: $OUT_DIR"; exit 1; }
command -v qemu-aarch64-static >/dev/null || { echo "Falta qemu-aarch64-static"; exit 1; }

echo "[*] Output directory: $OUT_DIR"
echo "[*] Temporary staging: $STAGING"

# Create rootfs
mkdir -p "$CHROOT"

# Setup APK repositories
mkdir -p "$CHROOT/etc/apk"
cat << EOF > "$CHROOT/etc/apk/repositories"
${MIRROR}/${RELEASE}/main
${MIRROR}/${RELEASE}/community
${PMOS_MIRROR}/${PMOS_RELEASE}
EOF

# Copy DNS config
cp /etc/resolv.conf "$CHROOT/etc/"

# Copy QEMU static
mkdir -p "$CHROOT/usr/bin"
cp $(which qemu-aarch64-static) "$CHROOT/usr/bin/"

# Download and use apk.static
echo "[*] Downloading apk.static..."
wget -q https://gitlab.alpinelinux.org/api/v4/projects/5/packages/generic/v2.14.6/x86_64/apk.static -O "$STAGING/apk.static"
chmod a+x "$STAGING/apk.static"

# Bootstrap Alpine
echo "[*] Bootstrapping Alpine Linux..."
"$STAGING/apk.static" add -p "$CHROOT" --initdb -U --arch aarch64 --allow-untrusted alpine-base

# Install packages
echo "[*] Installing packages..."
chroot "$CHROOT" ash -l -c "
apk add --no-cache --allow-untrusted postmarketos-keys
apk add --no-cache \
    bridge-utils \
    chrony \
    dropbear \
    eudev \
    iptables \
    linux-postmarketos-qcom-msm8916 \
    modemmanager \
    msm-firmware-loader \
    networkmanager-cli \
    networkmanager-dnsmasq \
    networkmanager-tui \
    networkmanager-wifi \
    networkmanager-wwan \
    openrc \
    rmtfs \
    sudo \
    udev-init-scripts \
    udev-init-scripts-openrc \
    wireguard-tools \
    wireguard-tools-wg-quick \
    wpa_supplicant \
    nano \
    shadow
"

# Setup Alpine
echo "[*] Setting up Alpine..."
chroot "$CHROOT" ash -l -c "
echo ${USERNAME}:${PASSWORD}::::/home/${USERNAME}:/bin/ash | newusers
apk del shadow

rc-update add devfs sysinit
rc-update add dmesg sysinit
rc-update add udev sysinit
rc-update add udev-trigger sysinit
rc-update add udev-settle sysinit
rc-update add udev-postmount default
rc-update add hwclock boot
rc-update add modules boot
rc-update add sysctl boot
rc-update add hostname boot
rc-update add bootmisc boot
rc-update add mount-ro shutdown
rc-update add killprocs shutdown
rc-update add savecache shutdown
rc-update add dropbear default
rc-update add rmtfs default
rc-update add modemmanager default
rc-update add networkmanager default
"

# Sudo config
echo "${USERNAME} ALL=(ALL:ALL) NOPASSWD: ALL" > "$CHROOT/etc/sudoers.d/${USERNAME}"

# Udev rules
cat << EOF > "$CHROOT/etc/udev/rules.d/10-udc.rules"
ACTION=="add", SUBSYSTEM=="udc", RUN+="/sbin/modprobe libcomposite", RUN+="/usr/bin/gt load rndis-os-desc.scheme rndis"
EOF

cat << EOF > "$CHROOT/etc/udev/rules.d/99-nm-usb0.rules"
SUBSYSTEM=="net", ACTION=="add|change|move", ENV{DEVTYPE}=="gadget", ENV{NM_UNMANAGED}="0"
EOF

# Enable autologin on console
sed -i '/^tty/ s/^/#/' "$CHROOT/etc/inittab"
echo 'ttyMSM0::respawn:/bin/sh' >> "$CHROOT/etc/inittab"

# Hostname
echo "$HOST_NAME" > "$CHROOT/etc/hostname"
sed -i "/localhost/ s/$/ ${HOST_NAME}/" "$CHROOT/etc/hosts"

# Copy configs
echo "[*] Copying configs..."
mkdir -p "$CHROOT/etc/NetworkManager/system-connections"
cp configs/*.nmconnection "$CHROOT/etc/NetworkManager/system-connections/" 2>/dev/null || true
chmod 0600 "$CHROOT/etc/NetworkManager/system-connections/"* 2>/dev/null || true
sed -i '/\[main\]/a dns=dnsmasq' "$CHROOT/etc/NetworkManager/NetworkManager.conf"

# Custom DTBs
mkdir -p "$CHROOT/boot/dtbs/qcom"
cp dtbs/* "$CHROOT/boot/dtbs/qcom/" 2>/dev/null || true

mkdir -p "$CHROOT/boot/extlinux"
cat > "$CHROOT/boot/extlinux/extlinux.conf" <<EOF
TIMEOUT 10
DEFAULT alpine

LABEL alpine
    MENU LABEL Alpine Linux
    linux /vmlinuz
    fdt /dtbs/qcom/msm8916-generic-uf02.dtb
    append earlycon root=/dev/mmcblk0p14 console=ttyMSM0,115200 no_framebuffer=true rw rootwait
EOF

cat > "$CHROOT/etc/fstab" <<EOF
/dev/mmcblk0p13    /boot    ext2    defaults    0 2
/dev/mmcblk0p14    /        ext4    defaults    0 1
EOF

# USB gadget
install -Dm0755 configs/msm8916-usb-gadget.sh "$CHROOT/usr/sbin/msm8916-usb-gadget.sh"
install -Dm0755 configs/msm8916-usb-gadget.init "$CHROOT/etc/init.d/msm8916-usb-gadget"
install -Dm0644 configs/msm8916-usb-gadget.conf "$CHROOT/etc/msm8916-usb-gadget.conf"

# Enable USB gadget service
chroot "$CHROOT" ash -l -c "rc-update add msm8916-usb-gadget default" || true

# Create tarball
echo "[*] Creating tarball..."
tar cpzf "$STAGING/alpine_rootfs.tgz" \
    --exclude="root/*" \
    --exclude="usr/bin/qemu-aarch64-static" \
    -C "$CHROOT" .

# Copy to output directory
echo "[*] Copying rootfs to $OUT_DIR..."
rm -rf "$OUT_DIR/rootfs"
mkdir -p "$OUT_DIR/rootfs"
tar -C "$CHROOT" \
    --exclude="root/*" \
    --exclude="usr/bin/qemu-aarch64-static" \
    -cf - . | tar -C "$OUT_DIR/rootfs" -xf -

cp "$STAGING/alpine_rootfs.tgz" "$OUT_DIR/rootfs.tgz"

echo "[+] OK: Alpine rootfs ready in $OUT_DIR"
echo "    - $OUT_DIR/rootfs/ (directory)"
echo "    - $OUT_DIR/rootfs.tgz (tarball)"
ls -lh "$OUT_DIR/rootfs.tgz"
