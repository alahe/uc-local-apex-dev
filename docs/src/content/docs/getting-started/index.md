---
title: Getting Started
description: Quick setup guide for UC Local APEX Dev environment
sidebar:
  order: 1
---

import { Aside } from "@astrojs/starlight/components";

Get your Oracle 26ai database with APEX and ORDS running locally in just a few minutes. This guide will walk you through the complete setup process.

## Prerequisites

Before you begin, make sure you have the following installed:

- **Docker or Podman** — both are natively supported. The scripts auto-detect which engine is installed (preferring `docker` if both are present).
- **Compose** — either `docker compose` (v2 plugin, or the legacy `docker-compose` v1) or the native `podman compose` subcommand.
- **SQLcl** with "sql" command in PATH
- **Bash-compatible shell**

<Aside type="caution" title="Resource Requirements">
Make sure your virtual machine has enough resources allocated. **The default Podman VM will cause issues with Oracle**.

Recommended minimum:

- **4GB RAM**
- **3 CPUs**
- **35GB disk space**

[Learn more about Oracle container requirements](https://hartenfeller.dev/blog/oracle-23ai-container-wont-start-mac)

</Aside>

### Platform-Specific Notes

#### macOS Users

If you're using macOS, [read the Podman setup guide](/products/uc-local-apex-dev/docs/other/podman-on-mac) for additional configuration steps.

#### Windows Users

We recommend using WSL2 (Windows Subsystem for Linux) for the best experience. Follow these guides:

- [Install Ubuntu on WSL2](https://documentation.ubuntu.com/wsl/latest/howto/install-ubuntu-wsl2/).
- [Install docker in Ubuntu](https://docs.docker.com/engine/install/ubuntu/)
- [Install SQLcl in Linux](https://pacesettergraam.wordpress.com/2025/02/21/installing-sqlcl-in-ubuntu-linux-on-oci/)

## Quick Setup

### 1. Clone the Repository

```bash
git clone https://github.com/United-Codes/uc-local-apex-dev.git
cd uc-local-apex-dev
```

### 2. Make Scripts Executable

```bash
chmod +x ./install.sh ./local-26ai.sh ./setup.sh ./scripts/*.sh
```

### 3. Run the Installer

```bash
./install.sh
```

The installer does the full bootstrap end-to-end: it generates an `.env` file with a random SYS password, pulls the images, starts the containers, waits for the database, installs APEX with dev-friendly defaults, and configures ORDS. The whole flow takes roughly 15–20 minutes on a typical machine, mostly waiting on the Oracle DB to come up. When it finishes you'll see a `=== Done ===` banner with the next steps.

<details>
<summary>What install.sh does in detail</summary>

1. Checks that a container engine (`docker` or `podman`) with a compose command, `sql` (SQLcl), `unzip` and `curl`/`wget` are on your `PATH`.
2. Runs `./setup.sh` to generate `.env` with a random Oracle SYS password (skipped if `.env` already exists and contains all required keys).
3. Pulls the DB + ORDS container images.
4. Starts the stack with `<engine> compose up -d`.
5. Waits for the database to be ready (up to 25 min), then verifies the host can connect to it via SQLcl (so a broken local SQLcl/Java setup fails fast with a real error message).
6. Runs `./scripts/after-first-db-start.sh` non-interactively — installs APEX, applies dev-friendly defaults (disables archive logs, relaxes APEX password rules), and sets the APEX `INTERNAL`/`ADMIN` password to the same `ORACLE_PASSWORD` value from `.env`. The ORDS container finishes its own first-boot install in parallel during this step.
7. Waits for ORDS to finish its first-boot install (up to 15 min) and sets the ORDS PL/SQL gateway mode to `proxied` (the recommended setting for APEX).
8. Restarts the ORDS container so it picks up the new APEX module + config change, and waits for it to come back.

If any wait times out, the installer prints the relevant container logs and exits — re-running `./install.sh` is safe and picks up where it left off.

</details>

<Aside type="tip" title="Forcing the container engine">
If you have both Docker and Podman installed and want to force one, set `CONTAINER_CLI` before running any script:

```bash
CONTAINER_CLI=podman ./install.sh
```

</Aside>

<Aside type="note" title="Podman compose provider">
  On Podman we use the native `podman compose` subcommand (which delegates to a
  compose provider), not the standalone `podman-compose` — the latter doesn't
  support everything in this project's `docker-compose.yml`.

The provider talks to Podman's API socket. If `podman compose` fails with
_"Cannot connect to the Docker daemon at unix:///run/user/.../podman/podman.sock"_,
enable the rootless socket:

```bash
systemctl --user enable --now podman.socket
```

On a **headless server you use over SSH**, also enable lingering so the
socket survives after you log out:

```bash
loginctl enable-linger "$USER"
```

</Aside>

### 4. Log into APEX

Visit http://localhost:8181/ords/apex and log in:

| Field | Value |
|-------|-------|
| Workspace | `INTERNAL` |
| Username | `ADMIN` |
| Password | Value of `ORACLE_PASSWORD` from `.env` |

If you get an "Account Is Locked" message:

```sh
./scripts/unexpire-accounts.sh
```

If you don't want APEX to force you to change passwords:

```sh
./scripts/disable-password-expiration.sh
```

Optionally [set up local SSL/HTTPS](/products/uc-local-apex-dev/docs/getting-started/common-tasks/#ssl-configuration) for ORDS, or save disk space by removing the `apex` install folder:

```bash
rm -rf ./apex
```

### 5. PATH Configuration

For easier script access, add the repository to your PATH:

```bash
# Add to ~/.zshrc or ~/.bashrc
export PATH="/Users/username/path/to/uc-local-apex-dev:$PATH"
```

Then use scripts from anywhere:

```bash
local-26ai.sh create-user newproject
local-26ai.sh backup-all
local-26ai.sh stop
```

## Next Steps

Now that your environment is running:

1. **Create your first workspace**: `local-26ai.sh create-user myproject` — see [Creating Users](/products/uc-local-apex-dev/docs/getting-started/creating-users/)
2. **See everything this project can do**: check the [Command Reference](/products/uc-local-apex-dev/docs/reference/commands/) or run `local-26ai.sh --help`
3. **Start developing your APEX applications**

## Access Your Environment

Once setup is complete, you can access:

- **APEX**: http://localhost:8181/ords/apex
- **ORDS Landing**: http://localhost:8181/ords/\_/landing
- **Database**: localhost:1521 (Service: FREEPDB1)

### Default APEX Credentials

**INTERNAL workspace:**

| Field | Value |
|-------|-------|
| Workspace | `INTERNAL` |
| Username | `ADMIN` |
| Password | Value of `ORACLE_PASSWORD` from `.env` |

**Your own workspaces** (created with `create-user`):

| Field | Value |
|-------|-------|
| Workspace | Your workspace name (e.g., `MOVIES`) |
| Username | `ADMIN` or the schema name |
| APEX Password | `Welcome_1` |
| DB Schema Password | Value of `<NAME>_USER_PASSWORD` from `.env` |

:::note
The APEX login password (`Welcome_1`) is different from the database schema password (the generated `<NAME>_USER_PASSWORD` value in `.env`).
:::

### Environment Variables (`.env`)

All passwords and configuration are stored in the `.env` file (auto-generated by `setup.sh`, excluded from Git):

| Variable | Purpose | Used by |
|----------|---------|---------|
| `ORACLE_PASSWORD` | Oracle SYS password + APEX `INTERNAL`/`ADMIN` login | Scripts, SQLcl connections, APEX admin login |
| `ORACLE_PWD` | Same value as `ORACLE_PASSWORD` | Oracle DB container (requires this variable name) |
| `DEMO_USER_PASSWORD` | Database schema password for the default `DEMO` user | SQLcl, SQL Developer, DBeaver, other DB tools |
| `<NAME>_USER_PASSWORD` | Database schema password for user `<NAME>` (e.g., `MOVIES_USER_PASSWORD`) | Created by `create-user`, used for DB connections |
| `DB_CONN_BASE` | SQLcl connection name prefix | SQLcl stored connections |
| `DB_CONN_NAME` | SQLcl SYS connection name | SQLcl stored connections |
| `CONTAINER_NAME` | Docker container name for the database | Scripts, Docker commands |
| `DBSERVICENAME` | Oracle database service name | ORDS, SQLcl connections |
| `DBHOST` | Database hostname (inside Docker network) | ORDS container connection |
| `DBPORT` | Database listener port | All database connections |
| `FORCE_SECURE` | Force HTTPS-only for ORDS | ORDS configuration |
| `DB_IMAGE_REPO` | Container registry host for Oracle Database (`container-registry.oracle.com` or company mirror like JFrog) | `docker-compose.yml` |
| `ORDS_IMAGE_REPO` | Container registry host for Oracle ORDS (`container-registry.oracle.com` or company mirror like JFrog) | `docker-compose.yml` |

