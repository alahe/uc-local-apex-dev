# UC Local APEX Dev

**Get Oracle 26ai with APEX and ORDS running in minutes. Automate the tedious parts of local APEX development.**

A containerized development environment (works with Docker, Podman, or any container runtime) that automates common tasks and lets you focus on building APEX applications.

**⚠️ This is not for production use!** Passwords stored in plain text, security features relaxed. For local development only.

## Prerequisites

- **Docker or Podman** (or any docker-compatible container runtime)
  - Allocate at least **4 GB RAM** and **3 CPUs** to your VM. The default Podman VM is too small for Oracle — [learn more](https://hartenfeller.dev/blog/oracle-23ai-container-wont-start-mac)
  - `docker compose` or `podman-compose`
- **SQLcl** with `sql` command in your PATH (if missing, `install.sh` can auto-install it via `sqlv`)
- **Bash-compatible shell** (on Windows, use WSL2)
- **Optional**: [mkcert](https://github.com/FiloSottile/mkcert) for trusted HTTPS without browser warnings

> **On Mac?** See [Podman on macOS](docs/src/content/docs/other/podman-on-mac.md) for VM setup instructions.

> **On Windows?** Install [Podman Desktop](https://podman-desktop.io/) **first** (required). It bundles the Podman CLI and sets up the WSL2 machine automatically, which is by far the fastest way to get a working environment on Windows — install it before running WSL2/Ubuntu or any of the commands below.

## Quick Start

```bash
git clone https://github.com/alahe/uc-local-apex-dev.git
cd uc-local-apex-dev
chmod +x ./install.sh ./local-26ai.sh ./setup.sh ./scripts/*.sh
./install.sh
```

The install script will:

1. Generate passwords and create `.env`
2. Pull Oracle 26ai and ORDS container images
3. Start the database and ORDS containers
4. Install APEX (this takes the longest)
5. Run post-install configuration

You can switch image sources anytime:

```bash
./local-26ai.sh switch-image-source oracle
./local-26ai.sh switch-image-source company
```

Profiles:

- `oracle` -> `container-registry.oracle.com`
- `company` -> your internal registry host, configured in `./company-registry.conf` (copy `company-registry.conf.example`)

### ADB Free: one-command setup

Prefer the lightweight Oracle ADB Free container instead of the full DB+ORDS+APEX stack? A single command
starts Podman (initializing a machine if none exists yet), installs the local registry CA certificate if one
is present under `.certs/`, switches the image source profile, and starts the container:

```bash
chmod +x ./local-26ai.sh ./scripts/*.sh ./scripts/adb/*.sh

./local-26ai.sh adb/bootstrap            # use the current/default image source
./local-26ai.sh adb/bootstrap oracle     # switch to the oracle profile, then start
./local-26ai.sh adb/bootstrap company    # switch to the company mirror profile, then start
./local-26ai.sh adb/bootstrap company --23ai   # switch profile + forward options to adb/start
```

Re-running it is safe — every step is a no-op once it's already satisfied. It does not automate a `podman
login` when the mirror requires authentication (credentials are never handled by scripts) — run that once
manually if needed.

To check progress while the image pulls or the database initializes:

```bash
podman ps -a                      # is the container up yet?
podman logs -f local-adb-free     # follow startup logs live
```

See [ADB Free: Checking status](docs/src/content/docs/getting-started/adb-free.md#checking-status) for details.

For enterprise mirrors behind proxy/SSO, keep these extra local setup steps documented for the team:

1. Recreate or initialize Podman machine with explicit host proxy variables when the machine image itself must be downloaded.
2. Ensure `NO_PROXY` and `no_proxy` inside the Podman machine include your internal registry host (see `company-registry.conf`).
3. Install the company registry CA certificate into the Podman machine under `/etc/containers/certs.d/<registry-host>/ca.crt` (`./local-26ai.sh adb/bootstrap` does this automatically when the certificate file is present under `.certs/`).
4. Use Artifactory's Docker "Subdomain method" endpoint for mirrored images (the repo key as a hostname prefix), not the path-based `.../artifactory/api/docker/<repo-key>` URL - standard Docker/Podman clients always ping the bare registry root (`/v2/`) without any path, which the path-based method cannot route.
5. If the registry requires authentication, run `podman login <registry-host>` before `adb/start`, `adb/bootstrap`, or `podman compose pull`.

Practical local convention:

- Copy `company-registry.conf.example` to `company-registry.conf` and fill in your registry host.
- Store the certificate in `.certs/registry/company-ca.crt`.
- Install it into the Podman machine with `./local-26ai.sh install-registry-ca`.

What should stay out of the public repository:

- Company CA certificate files
- Internal usernames, tokens, passwords, or login commands with embedded credentials
- Internal-only hostnames, proxy exceptions, or mirror paths if they are not approved for public disclosure

Recommended split:

- Keep the generic setup flow in this repository.
- Keep company-specific values and step-by-step enterprise bootstrap instructions in a private company repository or internal wiki.
- Use the sanitized template in [docs/src/content/docs/getting-started/enterprise-mirror-template.md](docs/src/content/docs/getting-started/enterprise-mirror-template.md) as the starting point for that private documentation.

Enable local git hook checks (recommended for mixed Windows/macOS teams):

```bash
./local-26ai.sh install-git-hooks
```

This installs a local `pre-commit` hook that blocks commits when CRLF is detected
in files that must be LF (`.sh`, `.yml`, `.env`, `.sql`, `.md`, ...).

**Follow the progress in the logs:**

```bash
docker logs -f local-26ai-ords
```

You'll see output like:

```
INFO : This container will start a service running ORDS <version> and APEX <version>.
INFO : CONN_STRING has been found in the container variables file.
INFO : Database connection established.
INFO : Apex is not installed on your database.
INFO : Installing APEX on your DB please be patient.
...
INFO : APEX has been installed.
INFO : Configuring APEX.
INFO : APEX ADMIN password has configured.
```

> **Note**: The exact ORDS and APEX versions depend on the container images defined in `docker-compose.yml` (currently ORDS `26.1.2`, DB `23.26.2.0`).

After ~15 minutes, services are available at:

| Service | URL |
|---------|-----|
| **APEX** | http://localhost:8181/ords/apex |
| **APEX (SSL)** | https://localhost:8443/ords/apex |
| **ORDS Landing** | http://localhost:8181/ords/\_/landing |
| **Database** | `localhost:1521` / Service: `FREEPDB1` |

### First Login

| Field | Value |
|-------|-------|
| Workspace | `INTERNAL` |
| Username | `ADMIN` |
| Password | Value of `ORACLE_PASSWORD` from `.env` |

```bash
# Create your first workspace
./local-26ai.sh create-user myproject

# See all commands
./local-26ai.sh --help
```

## ADB Free (Alternative)

Run Oracle ADB Free — a single container with DB, APEX, ORDS, and Database Actions. Supports **19c**, **23ai**, and **26ai**:

```bash
./local-26ai.sh adb/start           # 26ai (default)
./local-26ai.sh adb/start --19c     # 19c database
./local-26ai.sh adb/stop            # stop
```

| Service | URL |
|---------|-----|
| **APEX** | https://localhost:8443/ords/apex |
| **Database Actions** | https://localhost:8443/ords/sql-developer |
| **DB (TLS)** | `localhost:1521` |

**Login**:

| Field | Value |
|-------|-------|
| Username | `ADMIN` |
| Password | Value of `ADB_ADMIN_PASSWORD` from `.env.adb` |

See the [ADB Free documentation](docs/src/content/docs/getting-started/adb-free.md) for details.

## Container Management

```bash
# Start containers
./local-26ai.sh start

# Stop containers (graceful DB shutdown)
./local-26ai.sh stop

# View database logs
docker logs -f local-26ai

# View ORDS logs
docker logs -f local-26ai-ords
```

> **Tip**: The containers use resources in the background. Stop them when you're not developing to free up memory.

## Common Tasks

```bash
# Create a new schema + APEX workspace
./local-26ai.sh create-user myproject

# Delete all objects in a schema (keep the schema)
./local-26ai.sh clear-schema myproject

# Drop a user completely
./local-26ai.sh drop-user myproject

# Backup all schemas
./local-26ai.sh backup-all

# Backup a single schema
./local-26ai.sh backup-user myproject

# Restore from backup
./local-26ai.sh import-backup myproject

# Test an APEX app install in a clean schema
./local-26ai.sh test-app-install f100.sql

# Check database space usage
./local-26ai.sh used-space

# Reclaim unused disk space
./local-26ai.sh shrink-space
```

> **Tip**: Set up a shell alias for quick access:
> ```bash
> alias apex-dev='cd /path/to/uc-local-apex-dev && ./local-26ai.sh'
> ```

## Features

- ✅ One-command operations: create users, backups, clear schemas, test installs
- ✅ Create APEX workspaces and database schemas with optimal development grants
- ✅ All users automatically registered in SQLcl and VS Code for instant access
- ✅ Built-in Oracle DataPump backup and restore
- ✅ ORDS with SSL support for production-like local development
- ✅ Test APEX application installs repeatedly in isolated test schemas
- ✅ Full PL/SQL debugging support with VS Code SQL Developer
- ✅ APEX patch management (auto-apply during install)
- ✅ Post-install configuration (auto-create workspaces & ORDS pools)
- ✅ ADB Free support (19c / 23ai / 26ai with built-in APEX & ORDS)

## Documentation

🌐 [Online Documentation](https://www.united-codes.com/products/uc-local-apex-dev/docs/) · [GitHub](https://github.com/United-Codes/uc-local-apex-dev) · **📖 [Local Docs](docs/src/content/docs/index.mdx)** · [Browse locally](docs/src/content/docs/other/docs-server.md) (`./local-26ai.sh docs`)

| Guide | Description |
|-------|-------------|
| [Installation Guide](docs/src/content/docs/getting-started/index.md) | Full setup instructions |
| [ADB Free Container](docs/src/content/docs/getting-started/adb-free.md) | All-in-one DB + APEX + ORDS (19c/26ai) |
| [Common Tasks](docs/src/content/docs/getting-started/common-tasks.md) | Start/stop, SSL, maintenance |
| [Creating Users](docs/src/content/docs/getting-started/creating-users.md) | Schemas, workspaces, access |
| [Backups](docs/src/content/docs/getting-started/backups.md) | DataPump backup & restore |
| [Post-Install Config](docs/src/content/docs/getting-started/post-install.md) | Auto-create workspaces on install |
| [Upgrade APEX & Patches](docs/src/content/docs/migrations/upgrade-apex.md) | Upgrade APEX, apply PSBs |
| [PL/SQL Debugging](docs/src/content/docs/getting-started/plsql-debugging.md) | VS Code debugger setup |
| [Install Apps or Scripts](docs/src/content/docs/getting-started/install-apps-scripts.md) | Test app installs |
| [FAQ](docs/src/content/docs/other/faq.md) | Troubleshooting |
| [Podman on macOS](docs/src/content/docs/other/podman-on-mac.md) | Podman VM setup |

### For AI Coding Assistants

This repo ships [`.agents/skills/`](.agents/skills/) — repo-specific knowledge files (conventions, gotchas,
install workflows) that GitHub Copilot and other AI coding assistants can read automatically. See
[`repo-conventions`](.agents/skills/repo-conventions/SKILL.md) for shell/container/docs pitfalls, and
[`oracle-upstream-skills`](.agents/skills/oracle-upstream-skills/SKILL.md) for pointers to Oracle's own
official SQLcl/ORDS/APEX/Database skills at [github.com/oracle/skills](https://github.com/oracle/skills).

## Contributing

This is a fork of the [original project by United Codes](https://github.com/United-Codes/uc-local-apex-dev). For contributions to the core project, please submit issues and pull requests to the [upstream repository](https://github.com/United-Codes/uc-local-apex-dev).

For issues or improvements specific to this fork (ADB Free, Podman support, mkcert, patch management, etc.), use [this repository's issues](https://github.com/alahe/uc-local-apex-dev/issues).

## Acknowledgements

The following thanks are from the [original project](https://github.com/United-Codes/uc-local-apex-dev) by [United Codes](https://www.united-codes.com):

- The [contributors](https://github.com/United-Codes/uc-local-apex-dev/graphs/contributors) for their help
- Connor McDonald for his blog post on [space efficiently using the Free Edition](https://connor-mcdonald.com/2023/12/18/the-ultimate-database-free-edition/)
- Tim Hall for the [drop_all.sql](https://oracle-base.com/dba/script?category=miscellaneous&file=drop_all.sql) script
- Philipp Salvisberg for [helping me to figure out how to use the debugger](https://gist.github.com/PhilippSalvisberg/2f2853bc7a95fa86d9de9c0deab10602)
- Scott Spendolini for his blog post on [how to add self-signed certificates to ORDS](https://spendolini.blog/adding-ssl-to-your-ords-container)
- Matt Mulvaney for his blog post on [unexpiring ORDS accounts](https://mattmulvaney.hashnode.dev/unexpiring-the-ordspublicuser-user-for-apex)
- The database team for providing an ARM image for the Oracle database
- The ORDS team for providing an ARM image for ORDS

> *"The cherry on top would be Oracle making APEX patches free to download for everyone."*
> — United Codes

---

> **Fork Notice**: This repository is based on [uc-local-apex-dev](https://github.com/United-Codes/uc-local-apex-dev) by [United Codes](https://www.united-codes.com) and contains additional modifications (Podman native support, APEX patch management, post-install configuration, ADB Free support, environment reset, and documentation restructuring). These modifications are not affiliated with or supported by United Codes. For the original, unmodified version, please refer to the [upstream repository](https://github.com/United-Codes/uc-local-apex-dev).

[MIT License](LICENSE) · Original © 2024 United Codes
