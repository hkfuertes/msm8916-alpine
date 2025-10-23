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
    docker \
    docker-cli-compose \
    docker-openrc \
    dropbear \
    eudev \
    iptables \
    linux-postmarketos-qcom-msm8916 \
    modemmanager \
    msm-firmware-loader \
    nano \
    networkmanager-cli \
    networkmanager-tui \
    networkmanager-wifi \
    networkmanager-wwan \
    networkmanager-dnsmasq \
    openrc \
    rmtfs \
    shadow \
    sudo \
    udev-init-scripts \
    udev-init-scripts-openrc \
    wireguard-tools \
    wireguard-tools-wg-quick \
    e2fsprogs e2fsprogs-extra \
    neofetch \
    htop \
    wpa_supplicant \
    bash bash-completion
"

# Setup Alpine
echo "[*] Setting up Alpine..."
chroot "$CHROOT" ash -l -c "
# Create user
echo ${USERNAME}:${PASSWORD}::::/home/${USERNAME}:/bin/bash | newusers

# Set up bash for the user
printf 'PS1=\"\[\033[01;32m\]\u@\h\[\033[00m\]:\[\033[01;34m\]\w\[\033[00m\]$ \"\n' > /home/${USERNAME}/.bashrc
chown ${USERNAME}:${USERNAME} /home/${USERNAME}/.bash_profile

# Add user to docker group
addgroup ${USERNAME} docker

# Enable system services
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

# Enable application services
rc-update add chronyd default
rc-update add docker default
rc-update add dropbear default
rc-update add modemmanager default
rc-update add networkmanager default
rc-update add rmtfs default
"

# Sudo config
echo "${USERNAME} ALL=(ALL:ALL) NOPASSWD: ALL" > "$CHROOT/etc/sudoers.d/${USERNAME}"

# Docker configuration
echo "[*] Configuring Docker..."
mkdir -p "$CHROOT/etc/docker"
cat > "$CHROOT/etc/docker/daemon.json" <<'DOCKEREOF'
{
  "log-driver": "json-file",
  "log-opts": {
    "max-size": "10m",
    "max-file": "3"
  },
  "storage-driver": "overlay2",
  "iptables": true
}
DOCKEREOF

# Chrony configuration
echo "[*] Configuring Chrony..."
cat > "$CHROOT/etc/chrony/chrony.conf" <<'CHRONYEOF'
# NTP servers
server 0.pool.ntp.org iburst
server 1.pool.ntp.org iburst
server 2.pool.ntp.org iburst
server 3.pool.ntp.org iburst

# Allow NTP client access from local network
allow 192.168.5.0/24

# Sync system clock to hardware clock
rtcsync

# Drift file
driftfile /var/lib/chrony/chrony.drift

# Make chrony quickly sync on startup
makestep 1.0 3
CHRONYEOF

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
cp configs/network-manager/*.nmconnection "$CHROOT/etc/NetworkManager/system-connections/" 2>/dev/null || true
chmod 0600 "$CHROOT/etc/NetworkManager/system-connections/"* 2>/dev/null || true

mkdir -p "$CHROOT/etc/NetworkManager/dnsmasq-shared.d"
cat > "$CHROOT/etc/NetworkManager/dnsmasq-shared.d/usb0.conf" << 'EOF'
# Don't send default gateway (option 3) via DHCP
dhcp-option=3

# Only send IP address and DNS
interface=usb0
EOF

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
install -Dm0755 configs/usb-gadget/usb-gadget.sh "$CHROOT/usr/sbin/usb-gadget"
install -Dm0755 configs/usb-gadget/usb-gadget.init "$CHROOT/etc/init.d/usb-gadget"

# Enable USB gadget service
chroot "$CHROOT" ash -l -c "rc-update add usb-gadget default" || true

# Expand rootfs on first boot
install -Dm0755 configs/expand-rootfs/expand-rootfs.sh "$CHROOT/usr/sbin/expand-rootfs.sh"
install -Dm0755 configs/expand-rootfs/expand-rootfs.init "$CHROOT/etc/init.d/expand-rootfs"
chroot "$CHROOT" ash -l -c "rc-update add expand-rootfs boot" || true

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
echo "    - Kernel: linux-postmarketos-qcom-msm8916 from ${PMOS_RELEASE}"
echo "    - Docker: enabled and configured"
echo "    - Chrony: enabled with NTP servers"
echo "    - User '${USERNAME}' in docker group"
echo "    - $OUT_DIR/rootfs/ (directory)"
echo "    - $OUT_DIR/rootfs.tgz (tarball)"
ls -lh "$OUT_DIR/rootfs.tgz"
