#!/bin/bash
# install-airplay.sh

echo "=== Installing AirPlay Server (shairport-sync) ==="

# Instalar paquetes
apk add shairport-sync alsa-utils alsa-lib

# Cargar módulos USB audio
modprobe snd-usb-audio
echo "snd-usb-audio" >> /etc/modules

# Crear configuración
cat > /etc/shairport-sync.conf << 'EOF'
general = {
    name = "MSM8916 AirPlay";
    interpolation = "soxr";
    output_backend = "alsa";
}

alsa = {
    output_device = "hw:0,0";
    mixer_control_name = "PCM";
    mixer_device = "hw:0";
}

sessioncontrol = {
    session_timeout = 20;
}
EOF

# Habilitar servicio
rc-update add shairport-sync default

echo "=== Installation complete ==="
echo "Connect USB audio card and run: aplay -l"
echo "Edit /etc/shairport-sync.conf if needed"
echo "Start with: rc-service shairport-sync start"
