#!/bin/bash
# uninstall-airplay-stream.sh
# Remove AirPlay HTTP stream setup

echo "=== Uninstalling AirPlay HTTP Stream ==="

# 1. Stop services
echo "[*] Stopping services..."
sudo rc-service airplay-stream stop 2>/dev/null
sudo rc-service shairport-sync stop 2>/dev/null

# 2. Disable services
echo "[*] Disabling services..."
sudo rc-update del airplay-stream default 2>/dev/null
sudo rc-update del shairport-sync default 2>/dev/null

# 3. Remove service files
echo "[*] Removing service files..."
sudo rm -f /etc/init.d/airplay-stream
sudo rm -f /usr/local/bin/airplay-stream

# 4. Remove configuration
echo "[*] Removing configuration..."
sudo rm -f /etc/shairport-sync.conf

# 5. Remove pipe
echo "[*] Cleaning up pipes..."
sudo rm -f /tmp/shairport-audio

# 6. Kill any remaining processes
echo "[*] Killing remaining processes..."
sudo pkill -f airplay-stream 2>/dev/null
sudo pkill -f shairport-sync 2>/dev/null
sudo pkill -f ffmpeg 2>/dev/null

# 7. Optional: Remove packages (uncomment if desired)
# echo "[*] Removing packages..."
# sudo apk del shairport-sync ffmpeg

echo ""
echo "=== Uninstall Complete ==="
echo ""
echo "Services stopped and disabled"
echo "Configuration files removed"
echo ""
echo "Note: Packages (shairport-sync, ffmpeg) were NOT removed."
echo "To remove them manually, run:"
echo "  sudo apk del shairport-sync ffmpeg"
echo ""
