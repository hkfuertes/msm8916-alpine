#!/bin/bash

apt update
apt install -y --no-install-recommends \
    git \
    zip \
    android-sdk-libsparse-utils \
    autoconf \
    automake \
    binfmt-support \
    cmake \
    debian-archive-keyring \
    debootstrap \
    mmdebstrap \
    device-tree-compiler \
    fdisk \
    g++-aarch64-linux-gnu \
    gcc-aarch64-linux-gnu \
    gcc-arm-none-eabi \
    libtool \
    make \
    pkg-config \
    python3-cryptography \
    python3-pyasn1-modules \
    python3-pycryptodome \
    qemu-user-static \
    unzip \
    wget 

apt-get install -y --no-install-recommends \
    mmdebstrap qemu-user-static debian-archive-keyring ca-certificates gnupg

rm -rf /var/lib/apt/lists/*