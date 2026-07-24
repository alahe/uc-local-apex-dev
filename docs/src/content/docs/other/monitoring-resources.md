---
title: Monitoring Container Resource Usage
description: How to check how much CPU/RAM the local Oracle containers (incl. ADB Free) actually use, live, on Windows/WSL2, macOS, and Linux.
sidebar:
  order: 3
---

Oracle Database containers (both the DB + ORDS stack and ADB Free) can use a significant amount of CPU and
RAM. This page shows how to check what they're actually using right now, and explains a couple of gotchas
that can make the numbers look wrong.

## Quick options

| Tool | Shows | Notes |
|------|-------|-------|
| `podman stats <container>` | Live per-container CPU %, memory, network, block I/O | Ideal when it works — see [known limitation](#podman-stats-may-fail-on-rootless-podman--wsl2) below |
| `free -h` (inside WSL/Linux) | Real memory usage of the whole VM/host podman runs on | Most reliable number for "how much RAM is actually used" |
| Windows Task Manager → **Details** tab → `vmmemWSL` (or `vmmem`) | Aggregate CPU/RAM of the whole WSL2 utility VM | Covers **all** WSL distros/containers together, not just one container |
| `ps -eo pid,pcpu,rss,comm --sort=-rss` (inside WSL/Linux) | Per-process CPU % and RSS | Useful to see which processes are heaviest, but do **not** sum RSS for Oracle processes — see [gotcha](#dont-sum-per-process-rss-for-oracle) below |

## Windows / WSL2

### Live view of the whole WSL VM

```powershell
wsl -e watch -n 2 free -h
```

Refreshes every 2 seconds and shows total/used/free/available memory for the whole WSL2 VM that Podman runs
in (this includes the OS, Podman itself, and every running container).

### From Windows itself, without opening a WSL shell

1. Open **Task Manager** → **Details** tab → find the process named `vmmemWSL` (or `vmmem` on older builds).
2. Its **Working Set** / **Memory** column is the RAM currently used by the whole WSL2 utility VM.

Or from PowerShell:

```powershell
Get-Process -Name 'vmmemWSL' | Format-List Name, WorkingSet64, PM
```

`WorkingSet64` is resident memory, `PM` is private/committed memory — both in bytes.

This is an aggregate for **all** WSL distros and containers, not just one container — useful as a quick
health check, but not a per-container breakdown.

### Configured memory/CPU ceiling

WSL2 defaults to using up to ~50% of the host's RAM and all logical CPUs unless you cap it. Check/adjust the
cap in `%UserProfile%\.wslconfig`:

```ini
[wsl2]
memory=8GB
processors=4
```

## Per-container stats with Podman

```bash
podman stats local-adb-free
# or, for a one-shot snapshot instead of a live view:
podman stats --no-stream local-adb-free
```

### `podman stats` may fail on rootless Podman + WSL2

On some rootless Podman setups running inside WSL2 (especially with mirrored networking mode), `podman stats`
fails with an error like:

```
Error: unknown FS magic on "/run/user/1000/netns/netns-...": 1021994
```

This is a known Podman/WSL2 interaction issue with reading the network namespace's filesystem type, not a
problem with the container itself. Workarounds:

- Fall back to `free -h` / Task Manager as shown above for overall memory usage.
- Use `ps` inside the WSL distro to see per-process CPU/memory (see below).

### Per-process view as a fallback

```bash
wsl -e bash -c "ps -eo pid,pcpu,rss,comm --sort=-rss | head -20"
```

Lists the heaviest processes (by resident memory) system-wide, including the database background processes
(`ora_*`), the listener (`tnslsnr`), and ORDS (`java`).

#### Don't sum per-process RSS for Oracle

Oracle's background processes (`ora_pmon_*`, `ora_dbw0_*`, `ora_lgwr_*`, etc.) all attach to the same large
shared memory segment (the SGA). Each process's reported RSS in `ps`/`top` includes that **entire shared
segment**, not just its own private memory — so adding up the RSS column massively over-counts actual usage
(easily 3-4x too high). For a trustworthy total, use `free -h` (or the container's cgroup memory, if you can
read it) instead of summing `ps` output.

## Minimum requirements

See [ADB Free requirements](/products/uc-local-apex-dev/docs/getting-started/adb-free/#requirements) for the
baseline CPU/RAM each stack needs. If the live numbers above are consistently close to those minimums,
consider raising the WSL2/Podman machine's resource cap rather than running additional containers/branches
side by side.
