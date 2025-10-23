
# Alpine Linux for MSM8916 Devices

Alpine Linux rootfs builder for MSM8916-based devices (dongles and MiFi routers) with USB gadget, networking bridge, Docker, and LTE modem support.

## Features

- **Alpine Linux v3.20** with postmarketOS edge kernel (6.12.1+)
- **USB Gadget Mode**: RNDIS, ECM, NCM, ACM serial ports, and mass storage
- **Network Bridge**: br0 with DHCP server for USB tethering
- **WiFi Client**: WPA2 support via NetworkManager
- **LTE Modem**: ModemManager with QMI support (MSM8916 cellular)
- **Docker**: Pre-installed with user in docker group
- **NTP Sync**: Chrony for time synchronization
- **Auto-expand rootfs**: First boot partition and filesystem expansion
- **Dropbear SSH**: Lightweight SSH server
- **WireGuard**: VPN support built-in

## Requirements

### Host System

- **Docker** (for building in isolated environment)
- **Python 3** with `edl` tool (for flashing via EDL mode)

## Configuration

### variables.env

Edit `variables.env` to customize your build:

```
# System configuration
HOST_NAME="uz801a"
USERNAME="user"
PASSWORD="1"
```

### WiFi Configuration

Edit `configs/network-manager/wlan.nmconnection`:

```
[wifi]
ssid=YourSSID

[wifi-security]
psk=YourPassword
```

### USB Gadget Configuration

Edit `configs/usb-gadget/msm8916-usb-gadget.conf`:

```
# Enable/disable functions
ENABLE_RNDIS=1      # Windows/Android USB tethering
ENABLE_ECM=0        # Linux/macOS USB ethernet
ENABLE_NCM=0        # Modern USB ethernet
ENABLE_ACM=1        # Serial console over USB
ENABLE_UMS=0        # USB mass storage

# Network bridge
NETWORK_BRIDGE="br0"

# USB IDs
USB_VENDOR_ID="0x1d6b"
USB_PRODUCT_ID="0x0104"
USB_MANUFACTURER="MSM8916"
USB_PRODUCT="USB Gadget"
```

## Usage

### 1. Build everything (Docker)

```
# Create builder container (first time only)
make builder

# Build all images (rootfs, boot, recovery, GPT, firmware.zip)
make build
```

**Build output** in `files/`:
- `rootfs.tgz` - Alpine rootfs tarball
- `boot.img` - Kernel + initramfs boot image
- `recovery.img` - Recovery image (optional)
- `gpt_both0.bin` - GPT partition table for 4GB eMMC
- `firmware.zip` - Complete firmware package

### 2. Flash to device via EDL

#### Enter EDL Mode

1. Power off the device completely
2. Hold **Volume Up** button
3. Connect USB cable while holding button
4. Device enters EDL mode (no screen indication)

#### Flash with EDL

```
./flash.sh
```

### 3. First Boot

After flashing and reboot:
1. Device boots Alpine Linux (~30-45 seconds)
2. Rootfs automatically expands to fill eMMC
3. WiFi connects to configured network
4. USB gadget activates (RNDIS interface)
5. Bridge br0 creates with DHCP server (192.168.5.1/24)
6. SSH server starts on port 22

**Access via SSH:**
```
# Via WiFi (check router for IP)
ssh user@192.168.77.XXX

# Via USB
ssh user@192.168.5.1

# Default credentials
Username: user
Password: 1
```

## Components

### USB Gadget

The device exposes itself as a USB network adapter (RNDIS) when connected to a PC.

**Default configuration:**
- **Interface**: usb0
- **Bridge**: br0 (192.168.5.1/24)
- **DHCP**: Served by NetworkManager (192.168.5.2-254)
- **Functions**: RNDIS + ACM serial

**Service control:**
```
# Start/stop/restart
rc-service msm8916-usb-gadget start|stop|restart

# Check status
rc-service msm8916-usb-gadget status

# View logs
grep msm8916-usb-gadget /var/log/messages
```

### Network Bridge (br0)

Bridge interface that connects USB gadget, WiFi, and LTE for internet sharing.

**Configuration:**
- **IP**: 192.168.5.1/24
- **DHCP Range**: 192.168.5.2-254
- **NAT**: Enabled via NetworkManager shared method
- **Members**: usb0 (RNDIS interface)

**Manual control:**
```
# Activate bridge
nmcli connection up br0

# Check status
ip addr show br0

# Verify usb0 is in bridge
bridge link show
```

### Docker

Pre-installed and configured with overlay2 storage driver.

**User permissions:**
- User added to `docker` group (no sudo required)

**Configuration:** `/etc/docker/daemon.json`
```
{
  "log-driver": "json-file",
  "log-opts": {
    "max-size": "10m",
    "max-file": "3"
  },
  "storage-driver": "overlay2",
  "iptables": true,
  "bridge": "docker0",
  "fixed-cidr": "172.17.0.0/16"
}
```

**Usage:**
```
# Check version
docker --version

# Run test container
docker run hello-world

# View containers
docker ps -a
```

### LTE Modem

ModemManager with QMI support for cellular connectivity.

**Service:** `modemmanager` + `rmtfs`

**Check status:**
```
# List modems
mmcli -L

# Get modem details
mmcli -m 0

# Check connection
mmcli -m 0 --simple-status
```

**Manual connection:**
```
# Connect to network
nmcli connection up lte

# Check IP
ip addr show wwan0qmi0
```

### SSH Access

Dropbear SSH server on port 22.

**Default credentials:**
- Username: `user` (or configured in variables.env)
- Password: `1` (or configured in variables.env)
- Sudo: NOPASSWD enabled

**Connect:**
```
# Via WiFi
ssh user@192.168.77.XXX

# Via USB
ssh user@192.168.5.1
```

## First Boot

On first boot, the system will automatically:

1. ✅ Expand rootfs partition to fill eMMC
2. ✅ Resize ext4 filesystem
3. ✅ Start all services (NetworkManager, Docker, ModemManager, etc.)
4. ✅ Connect to configured WiFi
5. ✅ Create USB gadget (RNDIS interface)
6. ✅ Bridge usb0 to br0
7. ✅ Start DHCP server on br0
8. ✅ Sync time via Chrony

**Boot time:** ~30-45 seconds to full network connectivity

## Credits

- Alpine Linux Project
- postmarketOS Project
- Qualcomm MSM8916 mainline developers
- Linux USB Gadget subsystem
