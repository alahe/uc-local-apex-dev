---
title: ADB Free Container
description: Run Oracle Autonomous Database Free locally with pre-installed APEX, ORDS, and Database Actions.
sidebar:
  order: 8
---

Oracle ADB Free is an all-in-one container that bundles the database, APEX, ORDS, and Database Actions. It supports **19c**, **23ai**, and **26ai** database versions.

## Quick Start

```bash
# Start ADB Free (26ai, default)
./local-26ai.sh adb/start

# Start with 19c database
./local-26ai.sh adb/start --19c

# Start with 23ai database
./local-26ai.sh adb/start --23ai

# Stop
./local-26ai.sh adb/stop
```

On first run, the script generates passwords in `.env.adb`, pulls the container image, and configures trusted HTTPS certificates (if `mkcert` is installed).

## Access

Once the container is running (check with `docker logs -f local-adb-free`):

| Service | URL |
|---------|-----|
| **APEX** | https://localhost:8443/ords/apex |
| **Database Actions** | https://localhost:8443/ords/sql-developer |
| **DB (TLS)** | localhost:1521 |
| **DB (mTLS)** | localhost:1522 |
| **MongoDB API** | localhost:27017 |

### Login

| Field | Value |
|-------|-------|
| Username | `ADMIN` |
| Password | Value of `ADB_ADMIN_PASSWORD` from `.env.adb` |

## ADB Free vs DB + ORDS Stack

| Feature | DB + ORDS (default) | ADB Free |
|---------|-------------------|----------|
| Containers | 2 (DB + ORDS) | 1 (all-in-one) |
| APEX | Installed by scripts | Pre-installed |
| ORDS | Separate container | Built-in |
| Database Actions | ❌ | ✅ |
| MongoDB API | ❌ | ✅ (port 27017) |
| 19c support | ❌ | ✅ |
| DB size limit | 12 GB | 20 GB |
| Min resources | 4GB RAM, 3 CPU | **8GB RAM, 4 CPU** |
| Custom scripts | ✅ Full support | Limited |

:::caution[Port Conflict]
ADB Free and the main DB+ORDS stack use the same ports (1521, 8443). You can only run **one at a time**. Stop the main stack before starting ADB:

```bash
./local-26ai.sh stop
./local-26ai.sh adb/start
```
:::

## Available Versions

| Database | Image Tag | Architecture |
|----------|-----------|-------------|
| **26ai** | `latest-26ai` | ARM64 + AMD64 |
| **23ai** | `latest-23ai` | ARM64 + AMD64 |
| **19c** | `latest` | AMD64 only |

:::note[19c on Apple Silicon]
The 19c image is AMD64 only. On Apple Silicon Macs it runs via emulation, which is significantly slower. For better 19c performance, consider using [Colima](https://github.com/abiosoft/colima) with x86_64 emulation.
:::

## Requirements

- **Docker or Podman** with at least **4 CPUs** and **8 GB RAM** allocated
- For 19c on ARM: Colima or Rosetta emulation
- `/dev/fuse` device (required by the ADB container)
- **Optional**: [mkcert](https://github.com/FiloSottile/mkcert) for trusted HTTPS (no browser warnings)

## Configuration

The `.env.adb` file (auto-generated on first start, excluded from Git) contains:

```bash
ADB_ADMIN_PASSWORD=<generated>
ADB_WALLET_PASSWORD=<generated>
ADB_WORKLOAD_TYPE=ATP          # or ADW for Lakehouse
ADB_IMAGE_TAG=latest-26ai      # set by --19c / --23ai / --26ai
```

### Environment Variables (`.env.adb`)

| Variable | Purpose | Used by |
|----------|---------|---------|
| `ADB_ADMIN_PASSWORD` | `ADMIN` user password for APEX, Database Actions, and SQL connections | Browser login, SQL Developer, SQLcl |
| `ADB_WALLET_PASSWORD` | mTLS wallet password for secure database connections | mTLS connections on port 1522, wallet-based tools |
| `ADB_WORKLOAD_TYPE` | `ATP` (Transaction Processing) or `ADW` (Data Warehouse/Lakehouse) | Container initialization |
| `ADB_IMAGE_TAG` | Container image tag (`latest-26ai`, `latest-23ai`, `latest`) | `docker-compose.adb.yml` |

Change `ADB_WORKLOAD_TYPE` to `ADW` for a Lakehouse (data warehouse) workload instead of Transaction Processing.

## Trusted HTTPS (mkcert)

By default, the ADB container uses a self-signed SSL certificate, which causes browser warnings. The start script can automatically configure **trusted HTTPS** using [mkcert](https://github.com/FiloSottile/mkcert).

### Setup (one-time)

```bash
brew install mkcert
mkcert -install
```

This creates a local Certificate Authority and adds it to your system trust store. No ongoing processes or resource usage.

### How it works

When you run `./local-26ai.sh adb/start`:

1. If `mkcert` is installed and `.certs/localhost.pem` doesn't exist, certificates are generated automatically
2. The `.certs/` directory is bind-mounted into the container
3. ORDS is configured to use the trusted certificates
4. Browser shows a green lock 🔒 — no warnings

If `mkcert` is not installed, the container falls back to a self-signed certificate (browser warning can be bypassed by typing `thisisunsafe` on the Chrome warning page).

:::tip[Certificates persist across resets]
The certificates are stored on the host in `.certs/` (git-ignored) and mounted into the container. They survive volume resets and container recreation.
:::

## Compose File

The ADB container is defined in [docker-compose.adb.yml](file:///docker-compose.adb.yml), separate from the main `docker-compose.yml`. This keeps both stacks independent.
