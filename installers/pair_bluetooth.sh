#!/bin/sh
# pair_bluetooth.sh - Install/uninstall Bluetooth and pair device

# Function to show usage
show_usage() {
    echo "Usage: $0 [OPTIONS] <MAC_ADDRESS>"
    echo ""
    echo "Options:"
    echo "  -u, --uninstall    Uninstall Bluetooth packages and remove service"
    echo "  -h, --help         Show this help message"
    echo ""
    echo "Examples:"
    echo "  $0 AA:BB:CC:DD:EE:FF           # Install and pair device"
    echo "  $0 --uninstall                 # Uninstall Bluetooth"
    exit 1
}

# Function to uninstall
uninstall_bluetooth() {
    echo "=== Uninstalling Bluetooth ==="
    
    # Stop service if running
    if rc-service bluetooth status > /dev/null 2>&1; then
        echo "Stopping Bluetooth service..."
        rc-service bluetooth stop
    fi
    
    # Remove from startup
    if rc-status default | grep -q bluetooth; then
        echo "Removing Bluetooth from startup..."
        rc-update del bluetooth default
    fi
    
    # Uninstall packages
    PACKAGES="bluez bluez-alsa bluez-alsa-utils"
    for pkg in $PACKAGES; do
        if apk info -e "$pkg" > /dev/null 2>&1; then
            echo "Removing $pkg..."
            apk del "$pkg"
        fi
    done
    
    echo "=== Bluetooth uninstalled ==="
    exit 0
}

# Parse arguments
UNINSTALL=0

while [ $# -gt 0 ]; do
    case "$1" in
        -u|--uninstall)
            UNINSTALL=1
            shift
            ;;
        -h|--help)
            show_usage
            ;;
        -*)
            echo "Unknown option: $1"
            show_usage
            ;;
        *)
            MAC="$1"
            shift
            ;;
    esac
done

# Execute uninstall if requested
if [ $UNINSTALL -eq 1 ]; then
    uninstall_bluetooth
fi

# Check if MAC address provided
if [ -z "$MAC" ]; then
    echo "Error: MAC address required"
    show_usage
fi

echo "=== Installing Bluetooth packages ==="

# List of required packages
PACKAGES="bluez bluez-alsa bluez-alsa-utils"

# Update repositories
apk update

# Install each package if not present
for pkg in $PACKAGES; do
    if ! apk info -e "$pkg" > /dev/null 2>&1; then
        echo "Installing $pkg..."
        apk add "$pkg"
    else
        echo "$pkg is already installed"
    fi
done

echo "=== Configuring Bluetooth service ==="

# Start the service if not running
if ! rc-service bluetooth status > /dev/null 2>&1; then
    rc-service bluetooth start
    echo "Bluetooth service started"
fi

# Add to automatic startup if not present
if ! rc-status default | grep -q bluetooth; then
    rc-update add bluetooth default
    echo "Bluetooth added to startup"
fi

# Wait for service to be ready
sleep 2

echo "=== Pairing device $MAC ==="

# Power on adapter
bluetoothctl power on
sleep 1

# Configure agent
bluetoothctl pairable on
bluetoothctl agent on
bluetoothctl default-agent

# Scan for 10 seconds
echo "Scanning for devices..."
bluetoothctl scan on &
SCAN_PID=$!
sleep 10
kill $SCAN_PID 2>/dev/null

# Pair
echo "Pairing..."
bluetoothctl pair "$MAC"
sleep 2

# Mark as trusted
bluetoothctl trust "$MAC"

# Connect
bluetoothctl connect "$MAC"

echo ""
echo "=== Completed ==="
echo "Device $MAC paired and connected"
echo "To play audio use: bluealsa-aplay $MAC"
