---
title: Post-Install Configuration
description: Automatically create workspaces, users, and ORDS connection pools after a fresh install.
sidebar:
  order: 7
---

You can define a `post-install.conf` file that automatically creates workspaces, database users, and ORDS connection pools after `install.sh` (or `dev/reset`) completes. This is useful for:

- Setting up a consistent development environment across machines
- Automating team onboarding (everyone gets the same workspaces)
- Rebuilding your environment quickly after a reset

## Quick Start

```bash
# 1. Copy the example config
cp post-install.conf.example post-install.conf

# 2. Customize (e.g., add your project names)
# USERS=("demo" "myproject" "testing")

# 3. Run install — users are created automatically
./install.sh
```

## Configuration File

The `post-install.conf` file is a Bash script that defines two arrays:

### Users & Workspaces

```bash
# Creates a database schema + APEX workspace for each name
USERS=("demo" "myproject" "client_app")
```

Each entry runs `create-user.sh`, which:
- Creates the database schema with development grants
- Creates an APEX workspace with optimized settings
- Stores the password in `.env`
- Registers the connection in SQLcl

:::tip[Safe to re-run]
Existing users are automatically skipped. You can re-run `install.sh` or `./scripts/post-install.sh` without worrying about duplicates.
:::

### ORDS Connection Pools

```bash
# Format: ORDS_POOLS=("pool_name|db_host|db_port|db_service")
ORDS_POOLS=("reporting|26ai|1521|FREEPDB1")
```

This adds additional database connections to ORDS beyond the default pool. Useful for multi-database setups or connecting to external databases.

:::note
After adding new ORDS pools, restart ORDS to activate them:
```bash
./local-26ai.sh stop
./local-26ai.sh start
```
:::

## Running Manually

You can also run the post-install configuration at any time:

```bash
./scripts/post-install.sh
```

Or with a custom config file:

```bash
POST_INSTALL_CONF=./my-config.conf ./scripts/post-install.sh
```

## Example Output

```
=== Post-install configuration ===
Reading configuration from ./post-install.conf ...
loaded .env file
  ➕ Creating user: demo ...
    Schema DEMO created
    Workspace DEMO created
  ⏭  User MYPROJECT already exists — skipping.

Post-install complete:
  Users:      1 created, 1 skipped
  ORDS pools: 0 created, 0 skipped
```

## Git

The `post-install.conf` file is excluded from Git (via `.gitignore`) because it contains environment-specific settings. Only the `post-install.conf.example` template is tracked.
