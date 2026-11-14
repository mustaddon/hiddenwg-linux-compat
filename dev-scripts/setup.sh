#!/bin/bash

set -e

if [ ! -r /etc/os-release ]; then
    echo "Error: Cannot identify this distribution (/etc/os-release is missing)."
    exit 1
fi

. /etc/os-release

KERNEL_RELEASE="$(uname -r)"

run_privileged() {
    if [ "${EUID}" -eq 0 ]; then
        "$@"
    elif command -v sudo >/dev/null 2>&1; then
        sudo "$@"
    else
        echo "Error: Run this script as root or install sudo."
        return 1
    fi
}

case "$ID ${ID_LIKE:-}" in
    *debian*|*ubuntu*)
        run_privileged apt-get update
        run_privileged apt-get install -y \
            build-essential "linux-headers-$KERNEL_RELEASE" libelf-dev \
            pkg-config kmod perl
        ;;
    *arch*)
        KERNEL_BASE_FILE="/usr/lib/modules/$KERNEL_RELEASE/pkgbase"
        if [ -r "$KERNEL_BASE_FILE" ]; then
            KERNEL_BASE="$(<"$KERNEL_BASE_FILE")"
            KERNEL_HEADERS="${KERNEL_BASE}-headers"
        else
            KERNEL_HEADERS="linux-headers"
            echo "Warning: Could not identify the running Arch kernel package; installing linux-headers."
            echo "For a custom kernel, install its matching headers package instead."
        fi
        run_privileged pacman -S --needed --noconfirm \
            base-devel "$KERNEL_HEADERS" libelf pkgconf kmod perl
        ;;
    fedora*)
        run_privileged dnf install -y \
            gcc make "kernel-devel-$KERNEL_RELEASE" elfutils-libelf-devel \
            pkgconf-pkg-config kmod perl
        ;;
    centos*|rhel*|rocky*|almalinux*|*rhel*|*centos*)
        if command -v dnf >/dev/null 2>&1; then
            run_privileged dnf install -y \
                gcc make "kernel-devel-$KERNEL_RELEASE" elfutils-libelf-devel \
                pkgconf-pkg-config kmod perl
        elif command -v yum >/dev/null 2>&1; then
            run_privileged yum install -y \
                gcc make "kernel-devel-$KERNEL_RELEASE" elfutils-libelf-devel \
                pkgconfig kmod perl
        else
            echo "Error: Neither dnf nor yum was found."
            exit 1
        fi
        ;;
    *)
        echo "Error: Unsupported distribution '$ID'. Supported: Ubuntu, Debian, Fedora, CentOS/RHEL, Arch Linux."
        exit 1
        ;;
esac

KERNEL_BUILD_DIR="/lib/modules/$KERNEL_RELEASE/build"
if [ ! -f "$KERNEL_BUILD_DIR/Makefile" ]; then
    echo "Error: Complete kernel build files for '$KERNEL_RELEASE' were not found at '$KERNEL_BUILD_DIR'."
    echo "Install the matching kernel headers/devel package and reboot into that kernel."
    exit 1
fi