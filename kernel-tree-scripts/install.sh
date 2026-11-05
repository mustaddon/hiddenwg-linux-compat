#!/bin/bash

if [ "${EUID}" -ne 0 ]; then
    echo "You need to run this script as root"
    exit 1
fi

MOD_DIR=$(find "/lib/modules/$(uname -r)" -type d -name "wireguard")

if [ ! -d "$MOD_DIR" ]; then
    echo "Error: Wireguard module directory not found."
    exit 1
fi

function restartWg() {
    depmod -a
    modprobe wireguard
    dmesg | grep -i wireguard
    systemctl restart wg-quick@*
}

MOD_BAK=$"$MOD_DIR/_uninstall.hwg"

if [ -f "$MOD_BAK" ]; then
    echo "The patch is already installed. What do you want to do?"
    echo "   1) Reinstall"
    echo "   2) Uninstall"
    echo "   3) Exit"
    until [[ ${MENU_OPTION} =~ ^[1-3]$ ]]; do
        read -rp "Select an option [1-3]: " MENU_OPTION
    done
    case "${MENU_OPTION}" in
    2)
        modprobe -r wireguard
        mv -f "$MOD_BAK" "$MOD_DIR/wireguard.ko"
        restartWg
        exit 0
        ;;
    3)
        exit 0
        ;;
    esac
fi

if [ -f /etc/os-release ]; then
    . /etc/os-release
    if [[ "$ID" == 'ubuntu' ]] || [[ "$ID" == 'debian' ]]; then
		apt-get update
	    apt-get install -y libelf-dev linux-headers-$(uname -r) build-essential pkg-config wget git patch wireguard-tools resolvconf
    elif [[ "$ID" == 'fedora' ]] || [[ "$ID" == 'oracle' ]]; then
        dnf install -y elfutils-libelf-devel kernel-devel pkg-config @development-tools wget git patch wireguard-tools openresolv
	elif [[ "$ID" == 'centos' ]] || [[ "$ID" == 'almalinux' ]] || [[ "$ID" == 'rocky' ]]; then
		yum install -y elfutils-libelf-devel kernel-devel pkgconfig "@Development Tools" wget git patch
	elif [[ "$ID" == 'arch' ]]; then
        pacman -S --needed --noconfirm linux-headers base-devel pkg-config wget git patch wireguard-tools openresolv
	elif [[ "$ID" == 'alpine' ]]; then
		apk update
        apk add build-base linux-hardened-dev wget git patch wireguard-tools openresolv
	fi
fi

BRANCH="master"
START_DIR=$(pwd)
SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
TMP_DIR="$SCRIPT_DIR/_tmp"
rm -rf "$TMP_DIR"

trap "rm -rf $TMP_DIR; cd $START_DIR" EXIT SIGINT SIGTERM

function compileCompat() {
    git clone --branch "$BRANCH" --single-branch --depth 1 --no-checkout https://github.com/mustaddon/wireguard-linux-compat "$TMP_DIR"
    cd "$TMP_DIR"
    git sparse-checkout set src
    git checkout

    CODE_DIR="$TMP_DIR/src"

    if [ ! -d "$CODE_DIR" ]; then
        echo "Error: Directory '$CODE_DIR' does not exist."
        exit 1
    fi

    make -C "$CODE_DIR" -j$(nproc)
}

function applyPatch() {
    if [ -n "$1" ]; then
        wget --no-cache "https://raw.githubusercontent.com/mustaddon/wireguard-linux-compat/refs/heads/$BRANCH/kernel-tree-scripts/$1"

        if [ ! -f "$1" ]; then
            echo "Error: Patch '$1' not found."
            exit 1
        fi

        if patch -Np1 -f --dry-run < "$1" > /dev/null 2>&1; then
            echo "Applying patch '$1'..."
            patch -Np1 -f < "$1"
            echo "Patch '$1' applied."
        else
            echo "Error: Conflict detected! Patch '$1' not applied."
            patch -Np1 -f --dry-run < "$1"
            exit 1
        fi
    else
        echo "Error: Patch null argument."
        exit 1
    fi
}

function compile() {
    git clone --branch "v$(uname -r | cut -d'.' -f1,2)" --single-branch --depth 1 --no-checkout https://github.com/torvalds/linux "$TMP_DIR"
    cd "$TMP_DIR"
    git sparse-checkout set drivers/net/wireguard
    git checkout

    CODE_DIR="$TMP_DIR/drivers/net/wireguard"

    if [ ! -d "$CODE_DIR" ]; then
        echo "Error: Directory '$CODE_DIR' does not exist."
        exit 1
    fi

    cd "$CODE_DIR"

    applyPatch "wg.patch"

    wget --no-cache -N https://raw.githubusercontent.com/mustaddon/wireguard-linux-compat/refs/heads/$BRANCH/src/{hidden.h,hidden.c,version.h}

    make
}

MAJOR=$(uname -r | cut -d. -f1)
MINOR=$(uname -r | cut -d. -f2)

if [ "$MAJOR" -gt 5 ] || ([ "$MAJOR" -eq 5 ] && [ "$MINOR" -gt 5 ]); then
    compile
else
    compileCompat
fi

if [ ! -f "$CODE_DIR/wireguard.ko" ]; then
    echo "Error: File 'wireguard.ko' was not compiled."
    exit 1
fi

if [ ! -f "$MOD_BAK" ]; then
    cp "$MOD_DIR/wireguard.ko" "$MOD_BAK"
fi

modprobe -r wireguard
rm -rf "$MOD_DIR"/wireguard.ko*
cp "$CODE_DIR/wireguard.ko" "$MOD_DIR"
restartWg