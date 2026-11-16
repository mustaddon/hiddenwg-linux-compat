# [HiddenWG](https://github.com/mustaddon/hiddenwg) for Linux

This repository is a [fork](https://github.com/WireGuard/wireguard-linux-compat/) that adds only an obfuscation (traffic-masking) layer to the standard [WireGuard](https://www.wireguard.com/) protocol — and nothing else.

## Quick start

### 1) Install the driver

```bash
wget --no-cache -O hwg-install.sh https://raw.githubusercontent.com/mustaddon/hiddenwg-linux-compat/refs/heads/master/kernel-tree-scripts/install.sh
sudo bash hwg-install.sh
```

> [!IMPORTANT]
> This script replaces the standard WireGuard kernel module on the system.
> A backup is created automatically, and rerunning the script can be used to restore or revert the previous setup.

### 2) Set up the server

```bash
wget --no-cache -O wg-server.sh https://raw.githubusercontent.com/mustaddon/hiddenwg-linux-compat/refs/heads/master/kernel-tree-scripts/server.sh
sudo bash wg-server.sh
```

> [!NOTE]
> You can rerun the server script later to add new users, list existing ones, revoke access, or uninstall the setup.

## Building from source

The repository includes a dependency installer:

```bash
sudo bash dev-scripts/setup.sh
```

Linux 5.6 and later include WireGuard in the kernel, but HiddenWG still needs to be built as an external module. Build it against the full kernel tree for the running system:

```bash
make -C src KERNELDIR="/lib/modules/$(uname -r)/build" -j"$(nproc)"
```

The target kernel must have a complete build tree installed. Building alone does not install or load the module; `dev-scripts/deploy.sh` is the step used to deploy it on a system where WireGuard is available as a loadable module.

## License

This project is distributed under the same licensing terms as the upstream WireGuard compatibility tree, as referenced in the repository sources.
