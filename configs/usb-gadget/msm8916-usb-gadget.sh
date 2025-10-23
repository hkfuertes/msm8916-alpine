#!/bin/bash

GADGET_PATH="/sys/kernel/config/usb_gadget/msm8916"
CONFIG_FILE="/etc/msm8916-usb-gadget.conf"

# Load configuration from file
load_config() {
    if [ -f "$CONFIG_FILE" ]; then
        . "$CONFIG_FILE"
    fi
    
    # Set defaults if not configured
    : ${USE_NCM:=1}
    : ${ENABLE_OTG:=0}
}

# Update a single configuration value
update_config() {
    local key="$1"
    local value="$2"
    
    # Create config file if doesn't exist
    if [ ! -f "$CONFIG_FILE" ]; then
        cat > "$CONFIG_FILE" << 'EOF'
# MSM8916 USB Gadget Configuration
# Generated automatically - modify with enable_*/disable_* commands

USE_NCM=1           # 1 = NCM (Linux/Mac), 0 = RNDIS (Windows)
ENABLE_OTG=0        # 1 = OTG Host mode, 0 = Gadget mode
EOF
    fi
    
    # Update or add the key
    if grep -q "^${key}=" "$CONFIG_FILE"; then
        sed -i "s/^${key}=.*/${key}=${value}/" "$CONFIG_FILE"
    else
        echo "${key}=${value}" >> "$CONFIG_FILE"
    fi
    
    log "Configuration updated: ${key}=${value}"
}

log() {
    echo "$(date '+%Y-%m-%d %H:%M:%S') $@"
    logger -t usb-gadget "$@" 2>/dev/null || true
}

get_serial_number() {
    if [ -f /etc/machine-id ]; then
        sha256sum < /etc/machine-id | cut -d' ' -f1 | cut -c1-16
    else
        echo "$(date +%s)$(shuf -i 1000-9999 -n 1)"
    fi
}

generate_mac_address() {
    local prefix="$1"
    local serial="$(get_serial_number)"
    local hash="$(echo "${serial}${prefix}" | md5sum | cut -c1-12)"
    
    local b1="${hash:0:2}"
    local b2="${hash:2:2}"
    local b3="${hash:4:2}"
    local b4="${hash:6:2}"
    local b5="${hash:8:2}"
    local b6="${hash:10:2}"
    
    # Set locally administered, unicast
    b1="$(printf '%02x' $((0x${b1} & 0xfe | 0x02)))"
    
    echo "${b1}:${b2}:${b3}:${b4}:${b5}:${b6}"
}

setup_gadget() {
    load_config
    
    # Check if OTG host mode requested
    if [ "$ENABLE_OTG" = "1" ]; then
        log "OTG Host mode enabled - skipping gadget setup"
        echo "host" > /sys/class/udc/ci_hdrc.0/device/role 2>/dev/null || true
        return 0
    fi
    
    log "Setting up USB gadget"
    
    # Generate MAC addresses
    MAC_HOST=$(generate_mac_address "host")
    MAC_DEV=$(generate_mac_address "dev")
    
    modprobe libcomposite
    mountpoint -q /sys/kernel/config || mount -t configfs none /sys/kernel/config
    
    mkdir -p "${GADGET_PATH}"
    cd "${GADGET_PATH}"
    
    # Device descriptors
    echo "0x1d6b" > idVendor
    echo "0x0104" > idProduct
    echo "0x0100" > bcdDevice
    echo "0xEF" > bDeviceClass
    echo "0x02" > bDeviceSubClass
    echo "0x01" > bDeviceProtocol
    
    # Strings
    mkdir -p strings/0x409
    echo "$(get_serial_number)" > strings/0x409/serialnumber
    echo "MSM8916" > strings/0x409/manufacturer
    echo "USB Network" > strings/0x409/product
    
    # Configuration
    mkdir -p configs/c.1/strings/0x409
    
    # Network function
    if [ "$USE_NCM" = "1" ]; then
        log "Configuring NCM (Linux/Mac) - MAC: $MAC_HOST / $MAC_DEV"
        mkdir -p functions/ncm.usb0
        echo "$MAC_HOST" > functions/ncm.usb0/host_addr
        echo "$MAC_DEV" > functions/ncm.usb0/dev_addr
        ln -s functions/ncm.usb0 configs/c.1/
        echo "NCM" > configs/c.1/strings/0x409/configuration
        echo "0xc0" > configs/c.1/bmAttributes
    else
        log "Configuring RNDIS (Windows) - MAC: $MAC_HOST / $MAC_DEV"
        mkdir -p functions/rndis.usb0
        echo "$MAC_HOST" > functions/rndis.usb0/host_addr
        echo "$MAC_DEV" > functions/rndis.usb0/dev_addr
        ln -s functions/rndis.usb0 configs/c.1/
        echo "RNDIS" > configs/c.1/strings/0x409/configuration
        echo "0xe0" > configs/c.1/bmAttributes
        
        # Windows compatibility
        echo 1 > os_desc/use
        echo 0xcd > os_desc/b_vendor_code
        echo MSFT100 > os_desc/qw_sign
        echo RNDIS > functions/rndis.usb0/os_desc/interface.rndis/compatible_id
        echo 5162001 > functions/rndis.usb0/os_desc/interface.rndis/sub_compatible_id
        ln -s configs/c.1 os_desc
    fi
    
    # Enable gadget
    UDC=$(ls /sys/class/udc/ | head -1)
    echo "$UDC" > UDC
    
    log "USB gadget enabled on $UDC"
    log "Interface usb0 ready - NetworkManager will configure it"
}

teardown_gadget() {
    log "Tearing down USB gadget"
    
    [ ! -d "${GADGET_PATH}" ] && return 0
    
    cd "${GADGET_PATH}"
    
    # Disable gadget
    echo "" > UDC 2>/dev/null || true
    
    # Remove config
    rm -f configs/c.1/ncm.usb0 2>/dev/null || true
    rm -f configs/c.1/rndis.usb0 2>/dev/null || true
    rm -f os_desc/c.1 2>/dev/null || true
    rmdir configs/c.1/strings/0x409 2>/dev/null || true
    rmdir configs/c.1 2>/dev/null || true
    
    # Remove functions
    rmdir functions/ncm.usb0 2>/dev/null || true
    rmdir functions/rndis.usb0 2>/dev/null || true
    
    # Remove strings and gadget
    rmdir strings/0x409 2>/dev/null || true
    cd ..
    rmdir msm8916 2>/dev/null || true
}

status() {
    load_config
    
    echo "Configuration:"
    echo "  NCM Mode: $([ "$USE_NCM" = "1" ] && echo "Enabled (Linux/Mac)" || echo "Disabled (RNDIS/Windows)")"
    echo "  OTG Host: $([ "$ENABLE_OTG" = "1" ] && echo "Enabled" || echo "Disabled")"
    echo ""
    
    if [ "$ENABLE_OTG" = "1" ]; then
        echo "USB Mode: OTG Host"
        return 0
    fi
    
    if [ -d "${GADGET_PATH}" ] && [ -s "${GADGET_PATH}/UDC" ]; then
        echo "USB Gadget: Active"
        echo "Mode: $([ "$USE_NCM" = "1" ] && echo "NCM (Linux/Mac)" || echo "RNDIS (Windows)")"
        echo "UDC: $(cat ${GADGET_PATH}/UDC)"
        if ip link show usb0 >/dev/null 2>&1; then
            echo "Interface: usb0 (managed by NetworkManager)"
            if ip addr show usb0 | grep -q 'inet '; then
                echo "IP: $(ip addr show usb0 | grep 'inet ' | awk '{print $2}')"
            fi
        fi
        return 0
    else
        echo "USB Gadget: Inactive"
        return 1
    fi
}

enable_ncm() {
    update_config "USE_NCM" "1"
    echo "NCM mode enabled (Linux/Mac compatible)"
    echo "Run 'rc-service msm8916-usb-gadget restart' to apply changes"
}

disable_ncm() {
    update_config "USE_NCM" "0"
    echo "NCM mode disabled - RNDIS enabled (Windows compatible)"
    echo "Run 'rc-service msm8916-usb-gadget restart' to apply changes"
}

enable_otg() {
    update_config "ENABLE_OTG" "1"
    echo "OTG Host mode enabled"
    echo "Run 'rc-service msm8916-usb-gadget restart' to apply changes"
    echo "WARNING: This disables USB gadget functionality!"
}

disable_otg() {
    update_config "ENABLE_OTG" "0"
    echo "OTG Host mode disabled - Gadget mode enabled"
    echo "Run 'rc-service msm8916-usb-gadget restart' to apply changes"
}

show_config() {
    if [ -f "$CONFIG_FILE" ]; then
        echo "Current configuration ($CONFIG_FILE):"
        cat "$CONFIG_FILE"
    else
        echo "No configuration file found at $CONFIG_FILE"
        echo "Defaults will be used: USE_NCM=1, ENABLE_OTG=0"
    fi
}

case "$1" in
    start)
        teardown_gadget
        setup_gadget
        ;;
    stop)
        teardown_gadget
        ;;
    restart)
        teardown_gadget
        setup_gadget
        ;;
    status)
        status
        ;;
    enable_ncm)
        enable_ncm
        ;;
    disable_ncm)
        disable_ncm
        ;;
    enable_otg)
        enable_otg
        ;;
    disable_otg)
        disable_otg
        ;;
    show_config|config)
        show_config
        ;;
    *)
        echo "Usage: $0 {start|stop|restart|status|enable_ncm|disable_ncm|enable_otg|disable_otg|show_config}"
        exit 1
        ;;
esac
