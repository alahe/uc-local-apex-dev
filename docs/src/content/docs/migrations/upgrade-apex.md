---
title: Upgrade APEX
description: Guide on how to upgrade any APEX version in the containerized UC Local APEX Dev
sidebar:
  order: 1
---

You don't depend on any changes to this project to upgrade APEX. As soon as an update is available, you can follow these steps to upgrade APEX in your local environment.

## Versions >= 26.2: use the upgrade script

Starting with version 26.2, this project ships a `scripts/upgrade-apex.sh` script that automates downloading the latest APEX, running the installer, copying the images, and reapplying the `INTERNAL` workspace settings (extended session timeout, ACLs, etc.).

```sh
./scripts/upgrade-apex.sh
```

## Versions < 26.2: manual upgrade

### Download and unzip latest APEX version

```sh
# Using curl (pre-installed on macOS):
curl -fLO https://download.oracle.com/otn_software/apex/apex-latest.zip

# Or using wget:
wget https://download.oracle.com/otn_software/apex/apex-latest.zip

unzip apex-latest.zip
rm apex-latest.zip
rm -rf ./META-INF || true
```

### Perform the upgrade

```sh
cd apex
sql -name local-26ai-sys @apexins.sql TBS_APEX TBS_APEX TEMP /i/
exit;
```

(If you are still on 23ai use `SYSAUX` instead)

```sh
cd apex
sql -name local-23ai-sys @apexins.sql SYSAUX SYSAUX TEMP /i/
# (the connection is named local-23ai-sys on old 23ai installs)
exit;
```

### Update the images

```sh
cd ..
rm -rf ./apex-images || true
cp -r ./apex/images ./apex-images
```

If you get a popup error saying your files are outdated, you need to clear your browser cache.

## Apply APEX Patch Set Bundles

Patch Set Bundles (PSBs) are cumulative fixes published on [My Oracle Support](https://support.oracle.com) between APEX releases. They do not require a full APEX upgrade — they patch your existing version.

### 1. Download the patch

Look for the latest "Patch Set Bundle" for your APEX version on My Oracle Support (e.g., patch 39179920 for APEX 26.1).

### 2. Place the ZIP in the `apex-patches/` directory

```sh
cp ~/Downloads/p39179920_2610_Generic.zip ./apex-patches/
```

### 3. Apply the patch

```sh
./local-26ai.sh apply-patches
```

The script will:
- Skip any patches already installed (safe to re-run)
- Apply new patches in the correct order (by patch number)
- Copy updated static images to `apex-images/`

### 4. Restart ORDS

```sh
./local-26ai.sh stop
./local-26ai.sh start
```

### 5. Verify

```sql
-- In SQLcl or SQL Developer:
SELECT patch_number, patch_version, installed_on FROM apex_patches ORDER BY installed_on;
SELECT version_no, patch_applied FROM apex_release;
```

> **Automatic patching during install:** If you have patches in `apex-patches/` when running `install.sh` (or `dev/reset`), they are applied automatically after the APEX installation — no extra steps needed.
