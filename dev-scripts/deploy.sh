#!/bin/bash

if [ "${EUID}" -ne 0 ]; then
    echo "You need to run this script as root"
    exit 1
fi

MAJOR=$(uname -r | cut -d. -f1)
MINOR=$(uname -r | cut -d. -f2)

if [ "$MAJOR" -gt 5 ] || ([ "$MAJOR" -eq 5 ] && [ "$MINOR" -gt 5 ]); then
    echo "Linux kernel version must be 3.10-5.5"
    exit 1
fi

SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
CODE_DIR="$SCRIPT_DIR/../src"

make -C "$CODE_DIR" -j$(nproc)

if [ ! -f "$CODE_DIR/wireguard.ko" ]; then
    echo "Error: File 'wireguard.ko' was not compiled."
    exit 1
fi

MOD_DIR=$(find "/lib/modules/$(uname -r)" -type d -name "wireguard")

sudo modprobe -r wireguard
sudo rm -rf "$MOD_DIR"/wireguard.ko*
sudo cp "$CODE_DIR/wireguard.ko" "$MOD_DIR"
sudo modprobe wireguard
modinfo -F version wireguard
sudo systemctl restart wg-quick@*
