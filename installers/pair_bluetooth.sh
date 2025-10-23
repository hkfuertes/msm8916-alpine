#!/bin/sh
# pair_bluetooth.sh - Install Bluetooth and pair device

MAC="$1"

if [ -z "$MAC" ]; then
    echo "Usage: $0 <MAC_ADDRESS>"
    exit 1
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
