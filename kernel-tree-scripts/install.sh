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
                pkg-config git patch wireguard-tools resolvconf kmod
            ;;
        *fedora*)
            dnf install -y \
                gcc make "kernel-devel-$KERNEL_RELEASE" elfutils-libelf-devel \
                pkgconf-pkg-config git patch wireguard-tools kmod
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
                pkgconfig git patch wireguard-tools kmod
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
                base-devel "$kernel_headers" pkgconf git patch wireguard-tools kmod
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
            apk add build-base "$kernel_flavor" elfutils-dev pkgconf git patch \
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

remove_installed_module_files() {
    rm -f -- \
        "$MOD_DIR/wireguard.ko" \
        "$MOD_DIR/wireguard.ko.xz" \
        "$MOD_DIR/wireguard.ko.gz" \
        "$MOD_DIR/wireguard.ko.zst"
}

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
SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
REPO_DIR="$(cd -- "$SCRIPT_DIR/.." && pwd)"
TMP_DIR="$(mktemp -d "${TMPDIR:-/tmp}/hiddenwg-install.XXXXXX")"
trap 'rm -rf -- "$TMP_DIR"' EXIT

if [[ ! "$KERNEL_RELEASE" =~ ^([0-9]+)\.([0-9]+) ]]; then
    echo "Error: Cannot parse kernel version '$KERNEL_RELEASE'." >&2
    exit 1
fi
KERNEL_MAJOR="${BASH_REMATCH[1]}"
KERNEL_MINOR="${BASH_REMATCH[2]}"

if [ "$KERNEL_MAJOR" -gt 5 ] || { [ "$KERNEL_MAJOR" -eq 5 ] && [ "$KERNEL_MINOR" -gt 5 ]; }; then
    if [ ! -f "$REPO_DIR/kernel-tree-scripts/wg.patch" ] ||
        [ ! -f "$REPO_DIR/src/hidden.h" ] ||
        [ ! -f "$REPO_DIR/src/hidden.c" ] ||
        [ ! -f "$REPO_DIR/src/version.h" ]; then
        git clone --branch "$BRANCH" --single-branch --depth 1 \
            https://github.com/mustaddon/hiddenwg-linux-compat "$TMP_DIR/hiddenwg"
        REPO_DIR="$TMP_DIR/hiddenwg"
    fi

    UPSTREAM_TAG="v${KERNEL_MAJOR}.${KERNEL_MINOR}"
    git clone --branch "$UPSTREAM_TAG" --single-branch --depth 1 --no-checkout \
        https://github.com/torvalds/linux "$TMP_DIR/linux"
    git -C "$TMP_DIR/linux" sparse-checkout set drivers/net/wireguard
    git -C "$TMP_DIR/linux" checkout
    CODE_DIR="$TMP_DIR/linux/drivers/net/wireguard"

    if [ ! -f "$CODE_DIR/Makefile" ]; then
        echo "Error: WireGuard sources for upstream tag '$UPSTREAM_TAG' were not found." >&2
        exit 1
    fi

    PATCH_FILE="$REPO_DIR/kernel-tree-scripts/wg.patch"
    if ! patch -d "$CODE_DIR" -Np1 -f --dry-run < "$PATCH_FILE"; then
        echo "Error: Patch does not apply to upstream WireGuard '$UPSTREAM_TAG'." >&2
        exit 1
    fi
    patch -d "$CODE_DIR" -Np1 -f < "$PATCH_FILE"
    cp -- "$REPO_DIR/src/hidden.h" "$REPO_DIR/src/hidden.c" \
        "$REPO_DIR/src/version.h" "$CODE_DIR/"
    make -C "$CODE_DIR" KERNELDIR="$KERNEL_BUILD_DIR" -j"$(nproc)"
else
    if [ ! -f "$REPO_DIR/src/Makefile" ] || [ ! -f "$REPO_DIR/src/Kbuild" ]; then
        git clone --branch "$BRANCH" --single-branch --depth 1 \
            https://github.com/mustaddon/hiddenwg-linux-compat "$TMP_DIR/hiddenwg"
        REPO_DIR="$TMP_DIR/hiddenwg"
    fi
    CODE_DIR="$REPO_DIR/src"
    make -C "$CODE_DIR" KERNELDIR="$KERNEL_BUILD_DIR" -j"$(nproc)"
fi

NEW_MODULE="$CODE_DIR/wireguard.ko"
if [ ! -s "$NEW_MODULE" ]; then
    echo "Error: A non-empty 'wireguard.ko' was not built." >&2
    exit 1
fi

if ! MODULE_VERMAGIC="$(modinfo -F vermagic "$NEW_MODULE")"; then
    echo "Error: Could not read vermagic from the built module." >&2
    exit 1
fi
if [ "${MODULE_VERMAGIC%% *}" != "$KERNEL_RELEASE" ]; then
    echo "Error: Built module vermagic does not match '$KERNEL_RELEASE': $MODULE_VERMAGIC" >&2
    exit 1
fi

new_module_tmp=""
backup_tmp=""
backup_name_tmp=""

cleanup_module_temps() {
    [ -z "$new_module_tmp" ] || rm -f -- "$new_module_tmp"
    [ -z "$backup_tmp" ] || rm -f -- "$backup_tmp"
    [ -z "$backup_name_tmp" ] || rm -f -- "$backup_name_tmp"
}

install_module() {
    if [ ! -f "$MOD_BAK" ]; then
        backup_tmp="$(mktemp "$MOD_DIR/.wireguard-backup.XXXXXX")" || return 1
        backup_name_tmp="$(mktemp "$MOD_DIR/.wireguard-backup-name.XXXXXX")" || return 1
        cp -p -- "$MODULE_FILE" "$backup_tmp" || return 1
        printf '%s\n' "$(basename -- "$MODULE_FILE")" > "$backup_name_tmp" || return 1
        mv -f -- "$backup_name_tmp" "$MOD_BAK_NAME" || return 1
        backup_name_tmp=""
        mv -f -- "$backup_tmp" "$MOD_BAK" || return 1
        backup_tmp=""
    fi

    if [ -d /sys/module/wireguard ]; then
        modprobe -r wireguard || return 1
    fi

    new_module_tmp="$(mktemp "$MOD_DIR/.wireguard-module.XXXXXX")" || return 1
    cp -- "$NEW_MODULE" "$new_module_tmp" || return 1
    chmod 0644 "$new_module_tmp" || return 1
    mv -f -- "$new_module_tmp" "$MOD_DIR/wireguard.ko" || return 1
    new_module_tmp=""
    rm -f -- \
        "$MOD_DIR/wireguard.ko.xz" \
        "$MOD_DIR/wireguard.ko.gz" \
        "$MOD_DIR/wireguard.ko.zst" || return 1
    depmod -a "$KERNEL_RELEASE" || return 1
    modprobe wireguard || return 1
}

if ! install_module; then
    echo "Error: Module installation failed; attempting to restore the previous module." >&2
    cleanup_module_temps || true
    if [ -f "$MOD_BAK" ] && restore_original_module; then
        rm -f -- "$MOD_BAK" "$MOD_BAK_NAME"
        echo "Previous WireGuard module restored." >&2
    else
        echo "Error: Automatic rollback failed. The backup, if created, remains at '$MOD_BAK'." >&2
    fi
    exit 1
fi

restart_wg
modinfo -F version wireguard
