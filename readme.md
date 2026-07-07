# UC Local APEX Dev

**Get Oracle 26ai with APEX and ORDS running in minutes. Automate the tedious parts of local APEX development.**

A containerized development environment (works with Docker, Podman, or any container runtime) that automates common tasks and lets you focus on building APEX applications.

**⚠️ This is not for production use!** Passwords stored in plain text, security features relaxed. For local development only.

## Quick Start

```bash
git clone https://github.com/alahe/uc-local-apex-dev.git
cd uc-local-apex-dev
chmod +x ./install.sh ./local-26ai.sh ./setup.sh ./scripts/*.sh
./install.sh
```

After ~15 minutes:

| Service | URL |
|---------|-----|
| **APEX** | http://localhost:8181/ords/apex |
| **APEX (SSL)** | https://localhost:8443/ords/apex |
| **ORDS Landing** | http://localhost:8181/ords/\_/landing |
| **Database** | `localhost:1521` / Service: `FREEPDB1` |

**Login**: INTERNAL workspace → `ADMIN` / password from `.env` (`ORACLE_PASSWORD`)

```bash
# Create your first workspace
local-26ai.sh create-user myproject

# See all commands
local-26ai.sh --help
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

**Login**: `ADMIN` / password from `.env.adb` · See the [ADB Free documentation](docs/src/content/docs/getting-started/adb-free.md) for details.

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

## Contributing

If you have any ideas on how to improve this setup, please create an issue or a pull request.

I am especially thankful for improvements to the bash scripts.

## Special thanks

- The [contributors](https://github.com/United-Codes/uc-local-apex-dev/graphs/contributors) for their help
- Connor McDonald for his blog post on [space efficiently using the Free Edition](https://connor-mcdonald.com/2023/12/18/the-ultimate-database-free-edition/)
- Tim Hall for the [drop_all.sql](https://oracle-base.com/dba/script?category=miscellaneous&file=drop_all.sql) script
- Philipp Salvisberg for [helping me to figure out how to use the debugger](https://gist.github.com/PhilippSalvisberg/2f2853bc7a95fa86d9de9c0deab10602)
- Scott Spendolini for his blog post on [how to add self-signed certificates to ORDS](https://spendolini.blog/adding-ssl-to-your-ords-container)
- Matt Mulvaney for his blog post on [unexpiring ORDS accounts](https://mattmulvaney.hashnode.dev/unexpiring-the-ordspublicuser-user-for-apex)
- The database team for providing an ARM image for the Oracle database
- The ORDS team for providing an ARM image for ORDS

The cherry on top would be Oracle making APEX patches free to download for everyone.

---

> **Fork Notice**: This repository is based on [uc-local-apex-dev](https://github.com/United-Codes/uc-local-apex-dev) by [United Codes](https://www.united-codes.com) and contains additional modifications (Podman native support, APEX patch management, post-install configuration, ADB Free support, environment reset, and documentation restructuring). These modifications are not affiliated with or supported by United Codes. For the original, unmodified version, please refer to the [upstream repository](https://github.com/United-Codes/uc-local-apex-dev).

[MIT License](LICENSE) · Original © 2024 United Codes
