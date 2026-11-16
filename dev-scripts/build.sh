#!/bin/bash

KERNEL_BUILD_DIR="/lib/modules/$(uname -r)/build"
if [ ! -d "$KERNEL_BUILD_DIR" ]; then
    echo "Error: Kernel build directory '$KERNEL_BUILD_DIR' does not exist."
    exit 1
fi

SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
CODE_DIR="$SCRIPT_DIR/../src"

if ! make -C "$CODE_DIR" KERNELDIR="$KERNEL_BUILD_DIR" clean; then
    echo "Error: Failed to clean previous WireGuard build."
    exit 1
fi

if ! make -C "$CODE_DIR" KERNELDIR="$KERNEL_BUILD_DIR" -j"$(nproc)"; then
    echo "Error: Failed to build WireGuard for kernel '$(uname -r)'."
    exit 1
fi
