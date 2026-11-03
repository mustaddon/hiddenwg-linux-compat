# HiddenWG for Linux 3.10 - x.x

This repository is a [fork](https://github.com/WireGuard/wireguard-linux-compat/) that adds obfuscation to the standard [WireGuard](https://www.wireguard.com/) protocol.

## Driver installation script 
```bash
wget --no-cache -O hwg-install.sh https://raw.githubusercontent.com/mustaddon/wireguard-linux-compat/refs/heads/master/kernel-tree-scripts/install.sh
sudo bash hwg-install.sh
```

## Server setup script 
```bash
wget --no-cache -O wg-server.sh https://raw.githubusercontent.com/mustaddon/wireguard-linux-compat/refs/heads/master/kernel-tree-scripts/server.sh
sudo bash wg-server.sh
```
