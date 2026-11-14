# [HiddenWG](https://github.com/mustaddon/hiddenwg) for Linux

This repository is a [fork](https://github.com/WireGuard/wireguard-linux-compat/) that adds obfuscation to the standard [WireGuard](https://www.wireguard.com/) protocol.

## Driver installation script 

```bash
wget --no-cache -O hwg-install.sh https://raw.githubusercontent.com/mustaddon/hiddenwg-linux-compat/refs/heads/master/kernel-tree-scripts/install.sh
sudo bash hwg-install.sh
```

> [!IMPORTANT]
> This script replaces the standard WireGuard kernel module in Linux.
> A backup is created automatically, allowing you to revert the changes by running the script again.


## Server setup script
```bash
wget --no-cache -O wg-server.sh https://raw.githubusercontent.com/mustaddon/hiddenwg-linux-compat/refs/heads/master/kernel-tree-scripts/server.sh
sudo bash wg-server.sh
```

## Building the kernel module

Linux 5.6 and later include WireGuard in the kernel, but HiddenWG still needs
to be built as an external module. Before building, install the required
dependencies listed in `dev-scripts/setup.sh`:

```bash
bash dev-scripts/setup.sh
```

The setup script supports Ubuntu/Debian, Fedora, CentOS/RHEL, and Arch Linux.
It uses `sudo` when needed and requires headers matching the running kernel.

Then build it against the complete build tree for the target kernel:

```bash
make -C src KERNELDIR="/lib/modules/$(uname -r)/build" -j"$(nproc)"
```

The target kernel must have a complete build tree installed. Building does not
install or load the module; `dev-scripts/deploy.sh` handles deployment on a
system where WireGuard is available as a loadable module.
