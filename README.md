# HiddenWG for Linux

This repository is a [fork](https://github.com/WireGuard/wireguard-linux-compat/) that adds obfuscation to the standard [WireGuard](https://www.wireguard.com/) protocol.

## Driver installation script 
```bash
sudo bash <(wget --no-cache -qO- https://raw.githubusercontent.com/mustaddon/wireguard-linux-compat/refs/heads/master/kernel-tree-scripts/install.sh)
```

## Server setup script 
```bash
wget --no-cache -O wg-server.sh https://raw.githubusercontent.com/mustaddon/wireguard-linux-compat/refs/heads/master/kernel-tree-scripts/server.sh
sudo bash wg-server.sh
```
