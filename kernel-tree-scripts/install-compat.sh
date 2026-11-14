#!/bin/bash

set -Eeuo pipefail

if [ "${EUID}" -ne 0 ]; then
    echo "You need to run this script as root" >&2
    exit 1
fi

if [ ! -r /etc/os-release ]; then
    echo "Error: Cannot identify this distribution (/etc/os-release is missing)." >&2
    exit 1
fi

. /etc/os-release

KERNEL_RELEASE="$(uname -r)"
KERNEL_BUILD_DIR="/lib/modules/$KERNEL_RELEASE/build"

install_dependencies() {
    case "$ID ${ID_LIKE:-}" in
        *debian*|*ubuntu*)
            apt-get update
            apt-get install -y \
                build-essential "linux-headers-$KERNEL_RELEASE" libelf-dev \
                pkg-config wget git wireguard-tools resolvconf kmod
            ;;
        *fedora*)
            dnf install -y \
                gcc make "kernel-devel-$KERNEL_RELEASE" elfutils-libelf-devel \
                pkgconf-pkg-config wget git wireguard-tools kmod
            ;;
        centos*|rhel*|rocky*|almalinux*|*rhel*|*centos*)
            local package_manager
            if command -v dnf >/dev/null 2>&1; then
                package_manager=dnf
            elif command -v yum >/dev/null 2>&1; then
                package_manager=yum
            else
                echo "Error: Neither dnf nor yum was found." >&2
                return 1
            fi
            "$package_manager" install -y \
                gcc make "kernel-devel-$KERNEL_RELEASE" elfutils-libelf-devel \
                pkgconfig wget git wireguard-tools kmod
            ;;
        *arch*)
            local kernel_base_file="/usr/lib/modules/$KERNEL_RELEASE/pkgbase"
            local kernel_headers
            if [ -r "$kernel_base_file" ]; then
                kernel_headers="$(<"$kernel_base_file")-headers"
            else
                kernel_headers=linux-headers
                echo "Warning: Could not identify the running Arch kernel package." >&2
                echo "For a custom kernel, install its matching headers package." >&2
            fi
            pacman -S --needed --noconfirm \
                base-devel "$kernel_headers" pkgconf wget git wireguard-tools kmod
            ;;
        *alpine*)
            local kernel_flavor=linux-lts-dev
            case "$KERNEL_RELEASE" in
                *-virt) kernel_flavor=linux-virt-dev ;;
                *-edge) kernel_flavor=linux-edge-dev ;;
                *-hardened) kernel_flavor=linux-hardened-dev ;;
                *-lts) kernel_flavor=linux-lts-dev ;;
                *)
                    echo "Error: Cannot determine the Alpine kernel flavor for '$KERNEL_RELEASE'." >&2
                    echo "Install the matching linux-*-dev package manually." >&2
                    return 1
                    ;;
            esac
            apk update
            apk add build-base "$kernel_flavor" elfutils-dev pkgconf wget git \
                wireguard-tools kmod
            ;;
        *)
            echo "Error: Unsupported distribution '$ID'." >&2
            return 1
            ;;
    esac
}

install_dependencies

if [ ! -f "$KERNEL_BUILD_DIR/Makefile" ]; then
    echo "Error: Complete kernel build files for '$KERNEL_RELEASE' were not found at '$KERNEL_BUILD_DIR'." >&2
    echo "Install the matching kernel headers/devel package and reboot into that kernel." >&2
    exit 1
fi

if ! MODULE_FILE="$(modinfo -n wireguard 2>/dev/null)"; then
    echo "Error: Could not locate a loadable WireGuard module for kernel '$KERNEL_RELEASE'." >&2
    exit 1
fi
if [ -z "$MODULE_FILE" ] || [ "$MODULE_FILE" = "(builtin)" ] || [ ! -f "$MODULE_FILE" ]; then
    echo "Error: No loadable WireGuard module was found for kernel '$KERNEL_RELEASE'." >&2
    exit 1
fi
MOD_DIR="$(dirname -- "$MODULE_FILE")"
MOD_BAK="$MOD_DIR/_uninstall.hwg"
MOD_BAK_NAME="$MOD_BAK.original-name"

restore_original_module() {
    local original_name=wireguard.ko
    local restore_tmp

    if [ -r "$MOD_BAK_NAME" ]; then
        IFS= read -r original_name < "$MOD_BAK_NAME" || {
            echo "Error: Could not read original module filename from '$MOD_BAK_NAME'." >&2
            return 1
        }
    fi
    case "$original_name" in
        wireguard.ko|wireguard.ko.xz|wireguard.ko.gz|wireguard.ko.zst) ;;
        *)
            echo "Error: Invalid original module filename in '$MOD_BAK_NAME'." >&2
            return 1
            ;;
    esac

    restore_tmp="$(mktemp "$MOD_DIR/.wireguard-restore.XXXXXX")" || return 1
    if ! cp -- "$MOD_BAK" "$restore_tmp" || ! chmod 0644 "$restore_tmp"; then
        rm -f -- "$restore_tmp"
        return 1
    fi
    if ! remove_installed_module_files || ! mv -f -- "$restore_tmp" "$MOD_DIR/$original_name"; then
        rm -f -- "$restore_tmp"
        return 1
    fi
    depmod -a "$KERNEL_RELEASE" || return 1
    modprobe wireguard
}

restart_wg() {
    if command -v systemctl >/dev/null 2>&1; then
        systemctl restart 'wg-quick@*'
    elif command -v rc-service >/dev/null 2>&1; then
        local service
        local found=false
        for service in /etc/init.d/wg-quick*; do
            [ -x "$service" ] || continue
            found=true
            rc-service "$(basename -- "$service")" restart
        done
        if [ "$found" = false ]; then
            echo "Warning: No wg-quick OpenRC service was found." >&2
        fi
    else
        echo "Warning: Neither systemctl nor rc-service is available; WireGuard services were not restarted." >&2
    fi
}

remove_installed_module_files() {
    rm -f -- \
        "$MOD_DIR/wireguard.ko" \
        "$MOD_DIR/wireguard.ko.xz" \
        "$MOD_DIR/wireguard.ko.gz" \
        "$MOD_DIR/wireguard.ko.zst"
}

uninstall_module() {
    if [ ! -f "$MOD_BAK" ]; then
        echo "Error: Backup '$MOD_BAK' was not found." >&2
        return 1
    fi

    if [ -d /sys/module/wireguard ]; then
        modprobe -r wireguard
    fi
    restore_original_module
    rm -f -- "$MOD_BAK" "$MOD_BAK_NAME"
    restart_wg
    echo "Original WireGuard module restored."
}

if [ -f "$MOD_BAK" ]; then
    echo "The patch is already installed. What do you want to do?"
    echo "   1) Reinstall"
    echo "   2) Uninstall"
    echo "   3) Exit"
    until [[ "${MENU_OPTION:-}" =~ ^[1-3]$ ]]; do
        if ! read -r -p "Select an option [1-3]: " MENU_OPTION; then
            echo "Error: No menu selection was provided." >&2
            exit 1
        fi
    done
    case "$MENU_OPTION" in
        2)
            uninstall_module
            exit 0
            ;;
        3)
            exit 0
            ;;
    esac
fi

BRANCH="hwg-ai"
TMP_DIR="$(mktemp -d "${TMPDIR:-/tmp}/hiddenwg-install.XXXXXX")"
trap 'rm -rf -- "$TMP_DIR"' EXIT

git clone --branch "$BRANCH" https://github.com/mustaddon/hiddenwg-linux-compat "$TMP_DIR/repository"
CODE_DIR="$TMP_DIR/repository/src"

if [ ! -d "$CODE_DIR" ]; then
    echo "Error: Directory '$CODE_DIR' does not exist." >&2
    exit 1
fi

make -C "$CODE_DIR" KERNELDIR="$KERNEL_BUILD_DIR" -j"$(nproc)"

NEW_MODULE="$CODE_DIR/wireguard.ko"
if [ ! -s "$NEW_MODULE" ]; then
    echo "Error: A non-empty 'wireguard.ko' was not built." >&2
    exit 1
fi

MODULE_VERMAGIC="$(modinfo -F vermagic "$NEW_MODULE")"
if [ "${MODULE_VERMAGIC%% *}" != "$KERNEL_RELEASE" ]; then
    echo "Error: Built module vermagic does not match '$KERNEL_RELEASE': $MODULE_VERMAGIC" >&2
    exit 1
fi

if [ ! -f "$MOD_BAK" ]; then
    backup_tmp="$(mktemp "$MOD_DIR/.wireguard-backup.XXXXXX")"
    backup_name_tmp="$(mktemp "$MOD_DIR/.wireguard-backup-name.XXXXXX")"
    cp -p -- "$MODULE_FILE" "$backup_tmp"
    printf '%s\n' "$(basename -- "$MODULE_FILE")" > "$backup_name_tmp"
    mv -f -- "$backup_name_tmp" "$MOD_BAK_NAME"
    mv -f -- "$backup_tmp" "$MOD_BAK"
fi

if [ -d /sys/module/wireguard ]; then
    modprobe -r wireguard
fi

new_module_tmp="$(mktemp "$MOD_DIR/.wireguard-module.XXXXXX")"
cp -- "$NEW_MODULE" "$new_module_tmp"
chmod 0644 "$new_module_tmp"
mv -f -- "$new_module_tmp" "$MOD_DIR/wireguard.ko"
rm -f -- \
    "$MOD_DIR/wireguard.ko.xz" \
    "$MOD_DIR/wireguard.ko.gz" \
    "$MOD_DIR/wireguard.ko.zst"
depmod -a "$KERNEL_RELEASE"

if ! modprobe wireguard; then
    echo "Error: New module failed to load; attempting to restore the previous module." >&2
    if restore_original_module; then
        rm -f -- "$MOD_BAK" "$MOD_BAK_NAME"
        echo "Previous WireGuard module restored." >&2
    else
        echo "Error: Automatic rollback failed. The backup remains at '$MOD_BAK'." >&2
    fi
    exit 1
fi

restart_wg
modinfo -F version wireguard
