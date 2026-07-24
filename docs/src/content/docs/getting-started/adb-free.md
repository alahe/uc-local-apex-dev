---
title: ADB Free Container
description: Run Oracle Autonomous Database Free locally with pre-installed APEX, ORDS, and Database Actions.
sidebar:
  order: 8
---

Oracle ADB Free is an all-in-one container that bundles the database, APEX, ORDS, and Database Actions. It supports **19c**, **23ai**, and **26ai** database versions. See the [Architecture Overview](/products/uc-local-apex-dev/docs/reference/architecture/#adb-free-stack) for a diagram of what runs where and how it compares to the default DB + ORDS stack.

## Quick Start

```bash
# Start ADB Free (26ai, default)
./local-26ai.sh adb/start

# Start with 19c database
./local-26ai.sh adb/start --19c

# Start with 23ai database
./local-26ai.sh adb/start --23ai

# Start specific Oracle release tags
./local-26ai.sh adb/start --26ai-26.5.4.2
./local-26ai.sh adb/start --19c-26.2.4.2

# Start any custom tag from your registry
./local-26ai.sh adb/start --tag 26.5.4.2-26ai-amd64

# Stop
./local-26ai.sh adb/stop
```

On first run, the script generates passwords in `.env.adb`, pulls the container image, and configures trusted HTTPS certificates (if `mkcert` is installed).

### One-command setup

`adb/bootstrap` chains the steps above with the machine/registry setup needed for a fresh checkout: it
ensures a Podman machine exists and is running, installs a local registry CA certificate if one is present
under `.certs/`, switches the image source profile, and then runs `adb/start`.

```bash
./local-26ai.sh adb/bootstrap                  # use the current/default image source
./local-26ai.sh adb/bootstrap oracle           # switch to the oracle profile, then start
./local-26ai.sh adb/bootstrap company --23ai   # switch profile + forward options to adb/start
```

It does not run `podman login` for you — do that once manually if your registry requires authentication.

## Checking status

The first `adb/start` (or `adb/bootstrap`) run can take a while — it pulls a multi-GB image, then the
database needs time to initialize. Use these commands (in the same shell you used to start it, e.g. WSL) to
see what's going on:

```bash
# Is the image still downloading, or is the container up?
podman ps -a
# or: docker ps -a

# Follow the container's startup/init logs live (Ctrl+C to stop watching)
podman logs -f local-adb-free
# or: docker logs -f local-adb-free

# Follow an in-progress image pull started via compose
podman compose -f docker-compose.adb.yml logs -f
```

What to look for:

- `podman ps -a` shows no `local-adb-free` row yet → the image pull is still running in your terminal.
- `local-adb-free` shows `Up (health: starting)` → the container is up, the database is still initializing (this step can take several minutes on first run).
- `local-adb-free` shows `Up (healthy)` → ready to use, see [Access](#access) below.
- `local-adb-free` shows `Exited` or `Restarting` → check `podman logs local-adb-free` for the error.

:::note[No health status on WSL]
On WSL, rootless Podman usually has no working systemd user session, so `adb/start` runs the container with
`--no-healthcheck` to avoid a crash during startup. `podman ps` will just show `Up`, without a health state —
use `podman logs -f local-adb-free` instead to see when initialization has finished.
:::

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

## Managing containers & data

All persistent state (database files, wallet, APEX) lives in a single named volume, `adb-data`. `adb/start`
always recreates the `local-adb-free` **container** object on every run, but never touches that volume — so
data survives container restarts unless you explicitly remove the volume.

### Reset: discard all changes and start fresh

Removing the volume (not just the container) wipes the database completely and rebuilds it from scratch on
the next `adb/start`:

```bash
./local-26ai.sh adb/stop
podman volume rm adb-data      # or: docker volume rm adb-data
./local-26ai.sh adb/start
```

:::caution
This is irreversible. Back up anything important first (e.g. `podman cp local-adb-free:/u01/ords/wallet.zip .`
or a datapump export) if you might need it later.
:::

### Branch: snapshot the current state into a second, independent container

Use `adb/clone` to copy the current `adb-data` volume into a new one and run a second ADB Free container from
it, on auto-assigned free ports — so you can keep experimenting on the original container while a snapshot of
today's changes stays available to resume from later (or vice versa):

```bash
./local-26ai.sh adb/clone before-migration          # create + start the branch
./local-26ai.sh adb/clone before-migration --stop    # stop it (keeps its data)
./local-26ai.sh adb/clone before-migration           # resume it later (same volume/ports)
./local-26ai.sh adb/clone before-migration --remove  # delete the branch entirely
```

Notes:

- The original `local-adb-free` container is briefly stopped and restarted while the volume is copied, to
  avoid cloning a database mid-write.
- Ports (DB TLS/mTLS, HTTPS, MongoDB) are picked automatically, verified free, and remembered per branch name
  under `.certs/adb-clones/<branch>.env`, so re-running the same command reuses the same ports.
- Each branch gets its own container (`local-adb-free-<branch>`) and volume (`adb-data-<branch>`) — running
  several branches at once is supported as long as your machine has enough CPU/RAM for each.

### Pause: free up CPU/RAM without losing anything

To temporarily stop the container (e.g. it's using too many resources) and resume later with the exact same
state, stop the container directly instead of removing it — do **not** use `adb/start` to resume, since it
always recreates the container from scratch (harmless for the data, but slower and unnecessary):

```bash
podman stop local-adb-free     # frees CPU/RAM, container + data are kept
# ... later ...
podman start local-adb-free    # resumes with the exact same state
```

Not sure how much CPU/RAM the container is actually using right now? See
[Monitoring Container Resource Usage](/products/uc-local-apex-dev/docs/other/monitoring-resources/) for
live-monitoring commands on Windows/WSL2, macOS, and Linux.

## ADB Free vs DB + ORDS Stack

See also the [Architecture Overview](/products/uc-local-apex-dev/docs/reference/architecture/) for diagrams of both stacks and where passwords/APEX installs live.

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

Oracle naming convention:

| Database version | Latest tag | Specific release tag pattern |
|------------------|------------|-------------------------------|
| `26ai` | `latest-26ai` | `<release>-26ai` |
| `23ai` | `latest-23ai` | `<release>-23ai` |
| `19c` | `latest` | `<release>` |

| Database | Image Tag | Architecture |
|----------|-----------|-------------|
| **26ai** | `latest-26ai` | ARM64 + AMD64 |
| **23ai** | `latest-23ai` | ARM64 + AMD64 |
| **19c** | `latest` | AMD64 only |

Common examples from Oracle registry:

- `26.5.4.2-26ai`
- `26.5.4.2-26ai-amd64`
- `26.2.4.2-26ai`
- `26.2.4.2` (19c)

:::note[19c on Apple Silicon]
The 19c image is AMD64 only. On Apple Silicon Macs it runs via emulation, which is significantly slower. For better 19c performance, consider using [Colima](https://github.com/abiosoft/colima) with x86_64 emulation.
:::

## Requirements

- **Docker or Podman** with at least **4 CPUs** and **8 GB RAM** allocated
- For 19c on ARM: Colima or Rosetta emulation
- `/dev/fuse` device (required by the ADB container)
- **Optional**: [mkcert](https://github.com/FiloSottile/mkcert) for trusted HTTPS (no browser warnings)

See [Monitoring Container Resource Usage](/products/uc-local-apex-dev/docs/other/monitoring-resources/) to
check live CPU/RAM usage and confirm your setup meets these requirements.

## Configuration

The `.env.adb` file (auto-generated on first start, excluded from Git) contains:

```bash
ADB_ADMIN_PASSWORD=<generated>
ADB_WALLET_PASSWORD=<generated>
ADB_WORKLOAD_TYPE=ATP          # or ADW for Lakehouse
ADB_IMAGE_PATH=database/adb-free
ADB_IMAGE_TAG=latest-26ai      # set by --19c / --23ai / --26ai
```

### Environment Variables (`.env.adb`)

| Variable | Purpose | Used by |
|----------|---------|---------|
| `ADB_ADMIN_PASSWORD` | `ADMIN` user password for APEX, Database Actions, and SQL connections | Browser login, SQL Developer, SQLcl |
| `ADB_WALLET_PASSWORD` | mTLS wallet password for secure database connections | mTLS connections on port 1522, wallet-based tools |
| `ADB_WORKLOAD_TYPE` | `ATP` (Transaction Processing) or `ADW` (Data Warehouse/Lakehouse) | Container initialization |
| `ADB_IMAGE_PATH` | Image path after registry host (e.g. `database/adb-free` or mirrored `database/adb-free/adb-free`) | `docker-compose.adb.yml` |
| `ADB_IMAGE_TAG` | Container image tag (`latest-26ai`, `latest-23ai`, `latest`) | `docker-compose.adb.yml` |
| `ADB_IMAGE_REPO` | Container registry host (`ghcr.io` or company mirror like JFrog) | `docker-compose.adb.yml` |


Change `ADB_WORKLOAD_TYPE` to `ADW` for a Lakehouse (data warehouse) workload instead of Transaction Processing.

## Enterprise Mirror Setup

If your team uses an internal Artifactory or another mirrored registry for ADB images, validate these items before troubleshooting image pulls:

1. The registry URL must point to the Docker Registry API endpoint, not only the generic Artifactory repository path.
2. The Podman machine must have `NO_PROXY` and `no_proxy` configured for the internal registry host.
3. The internal registry CA certificate must be installed inside the Podman machine at `/etc/containers/certs.d/<registry-host>/ca.crt`.
4. If the mirror requires authentication, run `podman login <registry-host>` before pulling images.

Recommended local workflow for the CA file:

1. Save the certificate in `.certs/registry/company-ca.crt` on your machine.
2. Run `./local-26ai.sh install-registry-ca` to copy it into the Podman machine.

Typical failure patterns:

- `404` on `/v2/` usually means the mirror URL is not the Docker API endpoint.
- `407 Access Denied` usually means Podman is still reaching the registry through the corporate proxy instead of bypassing it with `NO_PROXY`.
- `connection reset by peer` while pulling directly from `container-registry.oracle.com` can mean the registry login worked, but the actual image blobs are being downloaded from Oracle Object Storage. In that case `NO_PROXY` and `no_proxy` may also need to include `objectstorage.us-phoenix-1.oraclecloud.com` and `.objectstorage.us-phoenix-1.oraclecloud.com`.
- `x509: certificate signed by unknown authority` means the internal CA is missing from the Podman machine.
- `EOF` during pull is often a secondary symptom of one of the proxy, auth, or CA issues above.

:::caution[Public vs private documentation]
Do not commit company CA certificates, internal proxy details, credentials, or internal-only bootstrap commands to a public repository. Keep the generic mirror workflow here, but store company-specific values and copy-paste commands in a private company repository or internal documentation system.
:::

If you need a starting point for private internal documentation, copy the sanitized template from [docs/src/content/docs/getting-started/enterprise-mirror-template.md](docs/src/content/docs/getting-started/enterprise-mirror-template.md) into your company repository or wiki and replace the placeholders there.

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
