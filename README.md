# Alpine Linux for MSM8916 Devices

Alpine Linux rootfs builder for MSM8916-based devices (dongles and MiFi routers) with USB gadget networking, Docker, and LTE modem support.

## Features

- **Alpine Linux v3.20** with postmarketOS edge kernel (6.12.1+)
- **USB Gadget Mode**: NCM (Linux/Mac) or RNDIS (Windows) networking
- **Direct USB Networking**: Simple usb0 interface with DHCP (no bridge complexity)
- **WiFi Client**: WPA2 support via NetworkManager
- **LTE Modem**: ModemManager with QMI support (MSM8916 cellular)
- **Docker**: Pre-installed with user in docker group
- **NTP Sync**: Chrony for time synchronization
- **Auto-expand rootfs**: First boot partition and filesystem expansion
- **Dropbear SSH**: Lightweight SSH server
- **WireGuard**: VPN support built-in
- **OTG Host Mode**: Optional USB host mode for peripherals

## Requirements

### Host System

- **Docker** (for building in isolated environment)
- **Python 3** with `edl` tool (for flashing via EDL mode)

## Configuration

### variables.env

Copy `variables.env.example` to `variables.env` and edit to customize your build:

```bash
cp variables.env.example variables.env
```

```bash
HOST_NAME="uz801a"
USERNAME="user"
PASSWORD="changeme"          # Required — build fails if not set
WIFI_SSID="MyNetwork"        # Optional — WiFi SSID to connect to
WIFI_PASS="MyPassword"       # Optional — WiFi password
DTB_FILE="msm8916-yiming-uz801v3.dtb"   # DTB to use in extlinux.conf

# Optional mirror overrides
RELEASE="v3.20"
PMOS_RELEASE="v24.12"
```

`variables.env` is git-ignored so your credentials are never committed.

### WiFi Configuration

Set `WIFI_SSID` and `WIFI_PASS` in `variables.env`. The build will substitute them
into the NetworkManager connection automatically.

### DTB Selection

Set `DTB_FILE` in `variables.env` to select which compiled DTB the bootloader uses.
See `dtbs/readme.md` for available options.

### USB Gadget Configuration

USB gadget uses simple configuration file `/etc/usb-gadget.conf`:

```bash
# MSM8916 USB Gadget Configuration

USE_NCM=1           # 1 = NCM (Linux/Mac), 0 = RNDIS (Windows)
ENABLE_OTG=0        # 1 = OTG Host mode, 0 = Gadget mode
```

**Management commands:**
```bash
# Enable NCM mode (Linux/Mac compatible)
usb-gadget enable_ncm

# Enable RNDIS mode (Windows compatible)
usb-gadget disable_ncm

# Enable OTG Host mode (for USB peripherals)
usb-gadget enable_otg

# Disable OTG (back to gadget mode)
usb-gadget disable_otg

# View current config
usb-gadget status

# Apply changes
rc-service usb-gadget restart
```

## Custom Device Trees

The build system can compile DTS (Device Tree Source) files from the upstream Linux kernel
and from the local `dts/` directory.

### Upstream DTS (auto-compiled)

`make build` automatically fetches the kernel DTS tree (cached in `.kernel-dts/`) and
compiles these upstream files:

- `msm8916-yiming-uz801v3.dts`
- `msm8916-thwc-uf896.dts`
- `msm8916-thwc-ufi001c.dts`

### Custom DTS

Add your own `.dts` files to the `dts/` directory. They are compiled with the same flags
and include paths as the upstream files, so you can reference kernel DTSI files:

```dts
// dts/msm8916-mydevice.dts
/dts-v1/;
#include "msm8916-ufi.dtsi"
// ... your customizations
```

Compile only DTS (without full build):

```bash
make dts
```

Output goes to `files/dtbs/`. See `dtbs/readme.md` for the list of precompiled fallback DTBs.

## Usage

### 1. Build everything (Docker)

```bash
# Create builder container (first time only)
make builder

# Build all images (rootfs, boot, recovery, GPT, firmware.zip)
make build
```

**Build output** in `files/`:
- `rootfs.bin` - Alpine rootfs sparse image
- `boot.bin` - Kernel + initramfs boot image
- `gpt_both0.bin` - GPT partition table for 4GB eMMC
- `firmware.zip` - Complete firmware package

### 2. Flash to device via EDL

#### Enter EDL Mode

1. Power off the device completely
2. Hold **Volume Up** button
3. Connect USB cable while holding button
4. Device enters EDL mode (no screen indication)

#### Flash with EDL

```bash
./flash.sh
```

### 3. First Boot

After flashing and reboot:
1. Device boots Alpine Linux (~30-45 seconds)
2. Rootfs automatically expands to fill eMMC
3. WiFi connects to configured network
4. USB gadget activates (NCM/RNDIS interface)
5. USB interface gets IP 192.168.42.1/24 with DHCP server
6. SSH server starts on port 22

**Access via SSH:**
```bash
# Via WiFi (check router for IP)
ssh user@192.168.77.XXX

# Via USB
ssh user@192.168.42.1

# Default credentials
Username: user
Password: (configured in variables.env)
```

## Components

### USB Gadget

The device exposes itself as a USB network adapter when connected to a PC.

**Default configuration:**
- **Interface**: usb0
- **IP**: 192.168.42.1/24
- **DHCP**: NetworkManager shared connection (192.168.42.10-100)
- **Mode**: NCM (Linux/Mac) or RNDIS (Windows)
- **MAC addresses**: Auto-generated from machine-id
- **No default route**: Host traffic stays on primary network

**Features:**
- ✅ Plug-and-play networking
- ✅ Automatic DHCP without extra dnsmasq
- ✅ No bridge complexity
- ✅ Doesn't steal host's default route
- ✅ Switchable NCM/RNDIS modes
- ✅ OTG Host mode support

**Service control:**
```bash
# Start/stop/restart
rc-service usb-gadget start|stop|restart

# Check status and current mode
usb-gadget status

# Switch modes
usb-gadget enable_ncm    # Linux/Mac
usb-gadget disable_ncm   # Windows (RNDIS)
usb-gadget enable_otg    # USB Host mode
```

### Network Configuration

**USB Networking (usb0):**
- **Method**: NetworkManager shared connection
- **IP**: 192.168.42.1/24
- **DHCP Range**: 192.168.42.10-192.168.42.100
- **Gateway**: Not advertised (host keeps existing default route)
- **DNS**: Optional, configurable

NetworkManager configuration in `/etc/NetworkManager/system-connections/usb0.nmconnection`:
```ini
[connection]
id=usb0
type=ethernet
interface-name=usb0
autoconnect=true

[ipv4]
method=shared
address1=192.168.42.1/24
never-default=true

[ipv6]
method=disabled
```

**WiFi (wlan0):**
- Managed by NetworkManager
- Auto-connects on boot
- Configuration in `/etc/NetworkManager/system-connections/wlan.nmconnection`

**LTE (wwan0qmi0):**
- Managed by ModemManager
- Configuration in `/etc/NetworkManager/system-connections/lte.nmconnection`

### Docker

Pre-installed and configured with overlay2 storage driver.

**User permissions:**
- User added to `docker` group (no sudo required)

**Configuration:** `/etc/docker/daemon.json`
```json
{
  "log-driver": "json-file",
  "log-opts": {
    "max-size": "10m",
    "max-file": "3"
  },
  "storage-driver": "overlay2",
  "iptables": true
}
```

**Usage:**
```bash
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
```bash
# List modems
mmcli -L

# Get modem details
mmcli -m 0

# Check connection
mmcli -m 0 --simple-status
```

**Manual connection:**
```bash
# Connect to network
nmcli connection up lte

# Check IP
ip addr show wwan0qmi0
```

### SSH Access

Dropbear SSH server on port 22.

**Default credentials:**
- Username: `user` (or configured in variables.env)
- Password: Configured in variables.env
- Sudo: NOPASSWD enabled

**Connect:**
```bash
# Via WiFi
ssh user@192.168.77.XXX

# Via USB
ssh user@192.168.42.1
```

## USB Gadget Modes

### NCM Mode (Default)

**Best for:** Linux and macOS

**Features:**
- High performance
- Native driver support in Linux 2.6.31+, macOS 10.9+
- No driver installation needed
- Supports up to 1 Gbps theoretical speed

**Enable:**
```bash
usb-gadget enable_ncm
rc-service usb-gadget restart
```

### RNDIS Mode

**Best for:** Windows

**Features:**
- Native Windows driver support
- Plug-and-play on Windows 7+
- Compatible with Android
- Lower performance than NCM

**Enable:**
```bash
usb-gadget disable_ncm
rc-service usb-gadget restart
```

### OTG Host Mode

**Best for:** USB peripherals (flash drives, keyboards, etc.)

**Features:**
- Enables USB host functionality
- Disables USB gadget mode
- Requires USB OTG adapter

**Enable:**
```bash
usb-gadget enable_otg
rc-service usb-gadget restart
```

**Warning:** WiFi or LTE connectivity required for remote access when in OTG mode!

## First Boot

On first boot, the system will automatically:

1. ✅ Expand rootfs partition to fill eMMC
2. ✅ Resize ext4 filesystem
3. ✅ Start all services (NetworkManager, Docker, ModemManager, etc.)
4. ✅ Connect to configured WiFi
5. ✅ Create USB gadget (NCM interface)
6. ✅ Configure usb0 with IP 192.168.42.1/24
7. ✅ Start DHCP server on usb0
8. ✅ Sync time via Chrony

**Boot time:** ~30-45 seconds to full network connectivity

## Credits

- @kinsamanka (https://github.com/kinsamanka/OpenStick-Builder): For almost all the project.
