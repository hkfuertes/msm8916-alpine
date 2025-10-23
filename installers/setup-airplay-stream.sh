#!/bin/bash
# setup-airplay-stream.sh
# iPhone -> AirPlay -> UF02 -> HTTP stream -> PC/VLC

echo "=== Setting up AirPlay to HTTP Stream ==="

# 1. Install packages
sudo apk add --no-cache shairport-sync ffmpeg

# 2. Configure Shairport with pipe output
sudo tee /etc/shairport-sync.conf > /dev/null << 'EOF'
general = {
    name = "UF02 AirPlay";
    output_backend = "pipe";
}

pipe = {
    name = "/tmp/shairport-audio";
}
EOF

# 3. Create streaming script
sudo tee /usr/local/bin/airplay-stream > /dev/null << 'EOF'
#!/bin/bash
# HTTP streaming from Shairport pipe

PIPE="/tmp/shairport-audio"
PORT=8080

echo "[*] Starting HTTP stream on port $PORT..."

# Create pipe if it doesn't exist
[ ! -p "$PIPE" ] && mkfifo "$PIPE"

# HTTP stream with ffmpeg
ffmpeg -f s16le -ar 44100 -ac 2 -i "$PIPE" \
    -f mp3 -ab 192k -ac 2 \
    -content_type audio/mpeg \
    -listen 1 \
    http://0.0.0.0:$PORT/stream.mp3
EOF

sudo chmod +x /usr/local/bin/airplay-stream

# 4. Create OpenRC service
sudo tee /etc/init.d/airplay-stream > /dev/null << 'EOF'
#!/sbin/openrc-run

name="AirPlay HTTP Stream"
command="/usr/local/bin/airplay-stream"
command_background=true
pidfile="/run/airplay-stream.pid"

depend() {
    need shairport-sync
}
EOF

sudo chmod +x /etc/init.d/airplay-stream

# 5. Enable services
sudo rc-update add shairport-sync default
sudo rc-update add airplay-stream default

# 6. Start services
sudo rc-service shairport-sync restart
sleep 2
sudo rc-service airplay-stream start

echo ""
echo "=== Setup Complete ==="
echo ""
echo "[OK] Shairport-Sync: Listening as 'UF02 AirPlay'"
echo "[OK] HTTP Stream: http://192.168.77.195:8080/stream.mp3"
echo ""
echo "Usage:"
echo "  1. iPhone -> Play music -> AirPlay -> 'UF02 AirPlay'"
echo "  2. PC -> VLC -> Open URL: http://192.168.77.195:8080/stream.mp3"
echo ""
echo "Or with ffplay:"
echo "  ffplay http://192.168.77.195:8080/stream.mp3"
echo ""
