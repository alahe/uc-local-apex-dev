---
title: Documentation Server
description: How to browse the project documentation as a styled website locally or share it on the network.
sidebar:
  order: 2
---

You can browse the project documentation as a styled website using the built-in documentation server. This is useful for a better reading experience or for sharing docs with your team.

## Start the Documentation Server

```bash
./local-26ai.sh docs
```

This will:
- Install npm dependencies automatically (first run only)
- Start a local Astro/Starlight server on port **4321**
- Open the documentation in your default browser

The server is available at: http://localhost:4321/products/uc-local-apex-dev/docs/

Press `Ctrl+C` to stop the server.

## Share on the Network

To make the documentation accessible from other machines (e.g., VMs, colleagues on the same network):

```bash
./local-26ai.sh docs --share
```

This exposes the server on all network interfaces (`0.0.0.0:4321`). The script will display your network IP so you can share the URL.

:::caution[Firewall]
If you're running inside a VM or behind a firewall, make sure port **4321** is open:

```bash
# Linux (ufw)
sudo ufw allow 4321

# Linux (iptables)
sudo iptables -A INPUT -p tcp --dport 4321 -j ACCEPT
```
:::

## Prerequisites

- **Node.js** and **npm** must be installed
- Dependencies (`docs/node_modules/`) are installed automatically on first run

## Reading Docs Without a Server

You can also read the documentation files directly in your IDE — they are standard markdown files located in `docs/src/content/docs/`. Use VS Code's built-in markdown preview (`Cmd+Shift+V` on macOS, `Ctrl+Shift+V` on Linux/Windows) to render them.
