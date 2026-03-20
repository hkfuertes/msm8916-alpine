#!/bin/bash

ARCH="$(dpkg --print-architecture)"

# Base packages (architecture-independent)
PACKAGES="
git
zip
autoconf
automake
binfmt-support
cmake
cpp
debian-archive-keyring
debootstrap
mmdebstrap
device-tree-compiler
fdisk
gcc-arm-none-eabi
libtool
make
pkg-config
python3-cryptography
python3-pyasn1-modules
python3-pycryptodome
ca-certificates
gnupg
unzip
wget
"

if [ "$ARCH" = "amd64" ]; then
    # Cross-compilers and QEMU for amd64 host targeting aarch64
    PACKAGES="$PACKAGES g++-aarch64-linux-gnu gcc-aarch64-linux-gnu qemu-user-static"
else
    # Native compilers on arm64 — no cross-compile needed
    PACKAGES="$PACKAGES gcc g++"
fi

apt update
apt install -y --no-install-recommends $PACKAGES
rm -rf /var/lib/apt/lists/*
