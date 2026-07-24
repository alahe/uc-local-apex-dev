---
title: Onboarding Checklist
description: A step-by-step onboarding guide for new team members — prerequisites, access, setup, daily usage, monitoring, and lifecycle commands for both the DB+ORDS and ADB Free stacks.
---

import { Tabs, TabItem } from "@astrojs/starlight/components";

This page is the "start here" checklist for a new team member setting up **uc-local-apex-dev** for the
first time. It intentionally links out to the detailed guides instead of duplicating them — use this page
to know *what* to do and *in what order*, then follow the links for the *how*.

Everything here applies to both stacks this project supports:

- **DB + ORDS** (default, two containers, full control) — see [Getting Started](/products/uc-local-apex-dev/docs/getting-started/)
- **ADB Free** (single all-in-one container, lighter setup, some limits) — see [ADB Free](/products/uc-local-apex-dev/docs/getting-started/adb-free/)

You only need one of them to develop APEX applications locally. If you're not sure which one your team
uses, ask your team lead — see [Architecture Overview](/products/uc-local-apex-dev/docs/reference/architecture/)
for a side-by-side comparison.

## 1. Hardware & VM Prerequisites

| | DB + ORDS | ADB Free |
|---|---|---|
| Minimum RAM | 4 GB | 8 GB |
| Minimum CPUs | 3 | 4 |
| Disk space | ~35 GB | ~35 GB+ |
| Extra requirements | — | `/dev/fuse` device |

:::caution[Resource Requirements]
The default Podman/Docker VM on macOS and Windows often does **not** meet these minimums out of the box.
Under-provisioning is the most common cause of "the database never finishes starting" problems. See the
[Resource Requirements note in Getting Started](/products/uc-local-apex-dev/docs/getting-started/#prerequisites)
and, on macOS, the [Podman setup guide](/products/uc-local-apex-dev/docs/other/podman-on-mac/).
:::

### Platform notes

- **macOS** — [read the Podman setup guide](/products/uc-local-apex-dev/docs/other/podman-on-mac/) before your first run.
- **Windows** — install [Podman Desktop](https://podman-desktop.io/) **first** (required — it bundles the Podman CLI and configures the WSL2 machine automatically, the fastest path to a working setup). Then install Ubuntu on WSL2 and SQLcl *inside* the WSL2 distro (links in [Getting Started → Windows Users](/products/uc-local-apex-dev/docs/getting-started/#windows-users)).
- **Linux** — no VM layer involved; containers run natively.

## 2. Required Software

A few things apply on every platform:

- **Git** — note that VS Code's built-in Source Control view is a UI on top of the `git` command-line
  tool, not a replacement for it. You still need the real `git` executable installed and on your `PATH`,
  even if you never type a `git` command yourself (Windows: [Git for Windows](https://git-scm.com/download/win),
  or `sudo apt install git` inside Ubuntu-on-WSL2 since this project's scripts run from there).
- A **Bash-compatible shell** (macOS/Linux built-in, WSL2 on Windows)
- Recommended: **VS Code** with an AI coding assistant (e.g. GitHub Copilot) — see [Day-to-Day Usage](#5-day-to-day-usage) below for why
- Optional: a browser-trusted HTTPS certificate. `create-self-signed-certificates` uses `openssl` (present on
  almost every system by default) first and only falls back to [mkcert](https://github.com/FiloSottile/mkcert)
  if `openssl` isn't available — most people never need to install mkcert at all. See
  [SSL Configuration](/products/uc-local-apex-dev/docs/getting-started/common-tasks/#ssl-configuration).

The container engine, Compose, and SQLcl differ enough by platform to call out separately:

<Tabs>
<TabItem label="Windows">

- **Container engine + Compose**: install [Podman Desktop](https://podman-desktop.io/). One install covers
  *both* — it bundles the Podman CLI and `podman compose`, and configures the WSL2 machine for you. No
  separate Compose install needed.
- **SQLcl**: if direct downloads from `download.oracle.com` are blocked for you, install the official
  [Oracle SQL Developer Extension for VS Code](https://marketplace.visualstudio.com/items?itemName=Oracle.sql-developer)
  instead — it bundles both SQLcl and a compatible JDK, so you don't need a separate Java install either.
  Use *that* bundled Java to run SQLcl, not a separate system JDK, to avoid version mismatches.

</TabItem>
<TabItem label="macOS">

- **Container engine + Compose**: Podman via Homebrew covers both — see the
  [Podman on Mac guide](/products/uc-local-apex-dev/docs/other/podman-on-mac/) for the exact commands.
- **SQLcl**: `brew install sqlcl` (also covered in the Podman on Mac guide).

</TabItem>
<TabItem label="Linux">

- **Container engine + Compose**: install `docker` with the `docker compose` plugin, or `podman` with
  `podman compose`, via your distro's package manager.
- **SQLcl**: [install manually or via your package manager](https://pacesettergraam.wordpress.com/2025/02/21/installing-sqlcl-in-ubuntu-linux-on-oci/), with `sql` on your `PATH`.

</TabItem>
</Tabs>

### Company-specific software & access

:::note[Fill this in privately]
Some organizations require software listed above to be requested through an internal self-service catalog
or ordering tool (for example a ServiceNow catalog, a JIRA Service Desk request, or an internal package
ordering tool) rather than a direct download, or provide an internal alternative to a tool above (for
example a different certificate-issuance client instead of mkcert, or a proxy-friendly SQLcl delivery
method). **This public repository intentionally does not name any specific internal tool** — follow the
same pattern as the
[Enterprise Mirror Setup Template](/products/uc-local-apex-dev/docs/getting-started/enterprise-mirror-template/)
and keep the real tool names, request links, and screenshots in your team's private wiki or internal repo.

A private onboarding page should cover, at minimum:

- Which of the tools in [Required Software](#2-required-software) (if any) must be requested through an internal catalog, and the exact request/item name
- Any internal alternative to a listed tool, and how to obtain/configure it
- Expected approval/provisioning time
- Who to contact if a request is stuck
:::

## 3. Access & Permissions

Pulling container images and, if used, reaching an internal APEX/patch mirror may require specific network
or directory-group access before your first `install.sh` run will succeed.

- **Container registry access** — if your team uses `IMAGE_SOURCE=company` (an internal mirror instead of
  `container-registry.oracle.com`), confirm with IT/your team lead that your account can pull images from
  that mirror. See [Enterprise Mirror Setup Template](/products/uc-local-apex-dev/docs/getting-started/enterprise-mirror-template/)
  for the generic troubleshooting flow (`404`/`407`/certificate errors).
- **Network access** — VPN or on-network access may be required to reach an internal registry or APEX/patch mirror.
- **Source control access** — access to this repository (and, if applicable, your organization's fork/mirror of it).

:::note[Fill this in privately]
As with software above, **do not add real Active Directory/IAM group names to this public repository.** In
your private wiki, list the specific group(s) a new team member must be added to (e.g. "registry pull access
group for `<registry-host>`") and who approves the request. This mirrors the
["What Must Stay Private"](/products/uc-local-apex-dev/docs/getting-started/enterprise-mirror-template/#what-must-stay-private)
section of the Enterprise Mirror Setup Template.
:::

## 4. Step-by-Step Setup

Once the above is sorted out, pick your platform below and follow that checklist top to bottom — each tab is
self-contained, so you shouldn't need to jump between them.

<Tabs>
<TabItem label="Windows">

**0. Platform prep (Windows-only, do this first):**

- [ ] Install [Podman Desktop](https://podman-desktop.io/) (**required** — bundles the Podman CLI and sets up the WSL2 machine automatically)
- [ ] Install [Ubuntu on WSL2](https://documentation.ubuntu.com/wsl/latest/howto/install-ubuntu-wsl2/)
- [ ] Install [SQLcl in Ubuntu/WSL2](https://pacesettergraam.wordpress.com/2025/02/21/installing-sqlcl-in-ubuntu-linux-on-oci/)
- [ ] Open a terminal **inside your Ubuntu-on-WSL2 distro** (not PowerShell/cmd) for every command below

**DB + ORDS (default):**

- [ ] `git clone https://github.com/United-Codes/uc-local-apex-dev.git && cd uc-local-apex-dev`
- [ ] `chmod +x ./install.sh ./local-26ai.sh ./setup.sh ./scripts/*.sh`
- [ ] `./install.sh` (generates `.env`, pulls images, starts containers, installs APEX — see [Getting Started → Quick Setup](/products/uc-local-apex-dev/docs/getting-started/#quick-setup) for the full breakdown)
- [ ] Log into APEX at `http://localhost:8181/ords/apex` with workspace `INTERNAL`, user `ADMIN`, and the `ORACLE_PASSWORD` value from `.env`
- [ ] Optional: enable HTTPS by setting `FORCE_SECURE="true"` in `.env` before running `install.sh` (see [SSL Configuration](/products/uc-local-apex-dev/docs/getting-started/common-tasks/#ssl-configuration))
- [ ] Optional: create your first schema + workspace with `./local-26ai.sh create-user <name>` — see [Creating Users](/products/uc-local-apex-dev/docs/getting-started/creating-users/)

**ADB Free (alternative):**

- [ ] Same clone + `chmod` steps as above
- [ ] `./local-26ai.sh adb/start` — see [ADB Free](/products/uc-local-apex-dev/docs/getting-started/adb-free/) for version flags and requirements
- [ ] Log into APEX / Database Actions at `https://localhost:8443/`

</TabItem>
<TabItem label="macOS">

**0. Platform prep (macOS-only, do this first):**

- [ ] Install [Homebrew](https://brew.sh/)
- [ ] Follow the [Podman on macOS](/products/uc-local-apex-dev/docs/other/podman-on-mac/) guide: `brew install podman`, `brew install sqlcl`, then `podman machine init`/`set`/`start` with at least 4GB RAM / 3 CPUs
- [ ] Add SQLcl to your `PATH` as described in that guide
- [ ] Run the remaining commands below in your normal Terminal/iTerm shell

**DB + ORDS (default):**

- [ ] `git clone https://github.com/United-Codes/uc-local-apex-dev.git && cd uc-local-apex-dev`
- [ ] `chmod +x ./install.sh ./local-26ai.sh ./setup.sh ./scripts/*.sh`
- [ ] `./install.sh` (generates `.env`, pulls images, starts containers, installs APEX — see [Getting Started → Quick Setup](/products/uc-local-apex-dev/docs/getting-started/#quick-setup) for the full breakdown)
- [ ] Log into APEX at `http://localhost:8181/ords/apex` with workspace `INTERNAL`, user `ADMIN`, and the `ORACLE_PASSWORD` value from `.env`
- [ ] Optional: enable HTTPS by setting `FORCE_SECURE="true"` in `.env` before running `install.sh` (see [SSL Configuration](/products/uc-local-apex-dev/docs/getting-started/common-tasks/#ssl-configuration))
- [ ] Optional: create your first schema + workspace with `./local-26ai.sh create-user <name>` — see [Creating Users](/products/uc-local-apex-dev/docs/getting-started/creating-users/)

**ADB Free (alternative):**

- [ ] Same clone + `chmod` steps as above
- [ ] `./local-26ai.sh adb/start` — see [ADB Free](/products/uc-local-apex-dev/docs/getting-started/adb-free/) for version flags and requirements
- [ ] Log into APEX / Database Actions at `https://localhost:8443/`

</TabItem>
<TabItem label="Linux">

**0. Platform prep (Linux-only, do this first):**

- [ ] Install Docker or Podman via your distro's package manager (no VM layer needed, containers run natively)
- [ ] Install [SQLcl](https://pacesettergraam.wordpress.com/2025/02/21/installing-sqlcl-in-ubuntu-linux-on-oci/) and make sure the `sql` command is on your `PATH`
- [ ] On Podman, also enable the rootless API socket: `systemctl --user enable --now podman.socket`

**DB + ORDS (default):**

- [ ] `git clone https://github.com/United-Codes/uc-local-apex-dev.git && cd uc-local-apex-dev`
- [ ] `chmod +x ./install.sh ./local-26ai.sh ./setup.sh ./scripts/*.sh`
- [ ] `./install.sh` (generates `.env`, pulls images, starts containers, installs APEX — see [Getting Started → Quick Setup](/products/uc-local-apex-dev/docs/getting-started/#quick-setup) for the full breakdown)
- [ ] Log into APEX at `http://localhost:8181/ords/apex` with workspace `INTERNAL`, user `ADMIN`, and the `ORACLE_PASSWORD` value from `.env`
- [ ] Optional: enable HTTPS by setting `FORCE_SECURE="true"` in `.env` before running `install.sh` (see [SSL Configuration](/products/uc-local-apex-dev/docs/getting-started/common-tasks/#ssl-configuration))
- [ ] Optional: create your first schema + workspace with `./local-26ai.sh create-user <name>` — see [Creating Users](/products/uc-local-apex-dev/docs/getting-started/creating-users/)

**ADB Free (alternative):**

- [ ] Same clone + `chmod` steps as above
- [ ] `./local-26ai.sh adb/start` — see [ADB Free](/products/uc-local-apex-dev/docs/getting-started/adb-free/) for version flags and requirements
- [ ] Log into APEX / Database Actions at `https://localhost:8443/`

</TabItem>
</Tabs>

:::tip[Team-standard workspaces]
If your team wants everyone to end up with the same set of schemas/workspaces after setup, look at
[Post-Install Configuration](/products/uc-local-apex-dev/docs/getting-started/post-install/) — it lets you
define a `post-install.conf` that `install.sh` runs automatically.
:::

## 5. Day-to-Day Usage

All scripts are invoked through the `local-26ai.sh` wrapper:

```bash
./local-26ai.sh <command> [args]
./local-26ai.sh --help          # list every available command
```

See the full list in the [Command Reference](/products/uc-local-apex-dev/docs/reference/commands/).

### Using an AI coding assistant

Because every script is a plain, documented shell command, an AI coding assistant (e.g. GitHub Copilot Chat
in VS Code) can run most of your day-to-day environment tasks for you — just describe what you want in
plain language:

| What you type | What it runs |
|---|---|
| *"Create a new schema and APEX workspace called `orders`, with compression enabled."* | `./local-26ai.sh create-user orders --compress` |
| *"Back up the `orders` schema before I start refactoring."* | `./local-26ai.sh backup-user orders` |
| *"Enable HTTPS for ORDS with a self-signed certificate."* | `./local-26ai.sh create-self-signed-certificates` (or set `FORCE_SECURE="true"` and re-run `install.sh`) |
| *"How much database space is `orders` using?"* | `./local-26ai.sh used-space` |
| *"Check the ORDS container logs for errors in the last 100 lines."* | `podman logs --tail 100 local-26ai-ords` (see [Monitoring](#6-monitoring--logs)) |
| *"Restart the environment without losing my data."* | `./local-26ai.sh stop && ./local-26ai.sh start` |

This works best when the assistant has the repository open as its workspace, so it can read `readme.md`,
[`reference/commands`](/products/uc-local-apex-dev/docs/reference/commands/), and the scripts themselves for
exact usage. This repo also ships `.agents/skills/` — repo-specific knowledge files that assistants like
GitHub Copilot pick up automatically, including a router to Oracle's own official SQLcl, ORDS, APEX, and
Database skills (`oracle-upstream-skills`) for anything beyond this repo's own scripts.

## 6. Monitoring & Logs

Before asking for help, check container status and logs yourself — or ask your AI assistant to do it:

- *"Check if the `local-26ai` and `local-26ai-ords` containers are healthy."*
- *"Look at the `local-26ai-ords` logs and tell me why APEX won't load."*
- *"How much CPU/RAM is the database container using right now?"*

Full commands (for both stacks, on Windows/WSL2, macOS, and Linux) are in
[Monitoring Container Resource Usage](/products/uc-local-apex-dev/docs/other/monitoring-resources/).

## 7. Stop, Start, Backup, and Restart

| Action | DB + ORDS | ADB Free | Data loss? |
|---|---|---|---|
| Stop (keep data) | `./local-26ai.sh stop` | `podman stop local-adb-free` | No |
| Start again | `./local-26ai.sh start` | `podman start local-adb-free` (do **not** use `adb/start` to resume — it recreates the container) | No |
| Restart (pick up config changes) | `./local-26ai.sh stop && ./local-26ai.sh start` | `podman restart local-adb-free` | No |
| Back up a schema | `./local-26ai.sh backup-user <name>` | Use Database Actions' export, or the same DataPump approach inside the container | No (creates a `.dmp` file) |
| Back up everything | `./local-26ai.sh backup-all` | — | No |
| Full reset (wipe and rebuild) | `./local-26ai.sh dev/reset` | `./local-26ai.sh adb/stop --remove` then `adb/start` | **Yes — deletes all data** |

:::caution[Full reset deletes data]
A full reset removes the database volume entirely. Always back up (`backup-all`/`backup-user`) anything you
need first. See [Common Tasks](/products/uc-local-apex-dev/docs/getting-started/common-tasks/) and
[Backups](/products/uc-local-apex-dev/docs/getting-started/backups/) for details, or
[ADB Free → Pause](/products/uc-local-apex-dev/docs/getting-started/adb-free/#pause-free-up-cpuram-without-losing-anything)
for a way to free up resources *without* losing data.
:::

## Next Steps

- [Architecture Overview](/products/uc-local-apex-dev/docs/reference/architecture/) — how the containers, volumes, and passwords fit together
- [Creating Users](/products/uc-local-apex-dev/docs/getting-started/creating-users/) — your first schema + APEX workspace
- [Common Tasks](/products/uc-local-apex-dev/docs/getting-started/common-tasks/) — SSL, resets, and other everyday operations
- [FAQ](/products/uc-local-apex-dev/docs/other/faq/)
