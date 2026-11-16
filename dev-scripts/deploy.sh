#!/bin/bash

if [ "${EUID}" -ne 0 ]; then
    echo "You need to run this script as root"
    exit 1
fi

KERNEL_BUILD_DIR="/lib/modules/$(uname -r)/build"
if [ ! -d "$KERNEL_BUILD_DIR" ]; then
    echo "Error: Kernel build directory '$KERNEL_BUILD_DIR' does not exist."
    exit 1
fi

SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
CODE_DIR="$SCRIPT_DIR/../src"

if ! make -C "$CODE_DIR" KERNELDIR="$KERNEL_BUILD_DIR" -j"$(nproc)"; then
    echo "Error: Failed to build WireGuard for kernel '$(uname -r)'."
    exit 1
fi

if [ ! -f "$CODE_DIR/wireguard.ko" ]; then
    echo "Error: File 'wireguard.ko' was not compiled."
    exit 1
fi

MODULE_FILE=$(modinfo -n wireguard 2>/dev/null || true)
if [ -z "$MODULE_FILE" ] || [ "$MODULE_FILE" = "(builtin)" ] || [ ! -f "$MODULE_FILE" ]; then
    echo "Error: No loadable WireGuard module was found for kernel '$(uname -r)'."
    exit 1
fi

MOD_DIR=$(dirname "$MODULE_FILE")

modprobe -r wireguard
rm -f -- "$MOD_DIR"/wireguard.ko*
cp "$CODE_DIR/wireguard.ko" "$MOD_DIR"
depmod -a "$(uname -r)"
modprobe wireguard
modinfo -F version wireguard
systemctl restart wg-quick@*
