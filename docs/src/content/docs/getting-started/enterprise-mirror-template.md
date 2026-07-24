---
title: Enterprise Mirror Setup Template
description: Sanitized template for documenting company-specific ADB mirror setup in a private repository or internal wiki.
---

Use this page as a copy template for your private company repository or internal wiki.

Do not fill in internal values in this public repository. Replace the placeholders only in a private location.

## Purpose

This template helps teams document the extra local setup required when ADB images are pulled from an internal mirror behind proxy, SSO, or custom CA infrastructure.

## Values To Replace In Private Docs

- `<registry-host>`
- `<docker-api-endpoint>`
- `<proxy-host>`
- `<proxy-port>`
- `<no-proxy-values>`
- `<certificate-file-name>`
- `<login-process>`

## Team Setup Checklist

1. Install Podman Desktop or Podman CLI on Windows, macOS, or Linux.
2. Initialize or recreate the Podman machine with the company proxy settings.
3. Verify `NO_PROXY` and `no_proxy` include `<registry-host>`.
4. Install the internal CA certificate into the Podman machine under `/etc/containers/certs.d/<registry-host>/ca.crt`.
5. Log in to the mirrored registry if authentication is required.
6. Switch the project image source to `company`.
7. Start ADB and confirm the image is pulled from the mirror.

## Example Private Configuration

```text
IMAGE_SOURCE=company
ADB_IMAGE_REPO=<docker-api-endpoint>
ADB_IMAGE_PATH=database/adb-free/adb-free
ADB_IMAGE_TAG=latest
```

## Example Private Bootstrap Steps

### 1. Configure Proxy On Host

Document the exact commands your team should use to set these values on the host:

```text
HTTP_PROXY=http://<proxy-host>:<proxy-port>
HTTPS_PROXY=http://<proxy-host>:<proxy-port>
NO_PROXY=<no-proxy-values>
```

### 2. Recreate Or Initialize Podman Machine

Document the company-approved command for creating the machine when proxy settings are required during image download.

### 3. Configure Proxy Bypass Inside Podman Machine

Document how to persist these values inside the machine:

```text
NO_PROXY=<no-proxy-values>
no_proxy=<no-proxy-values>
```

### 4. Install Company CA Certificate

Document:

- where the certificate file is distributed internally
- how to copy `<certificate-file-name>` into the machine
- how to place it under `/etc/containers/certs.d/<registry-host>/ca.crt`

### 5. Log In To Registry

Document the approved authentication flow for:

- SSO-assisted login
- username/password login
- token-based login

Do not store credentials in source control.

### 6. Start ADB

Document the exact team command, for example:

```bash
./local-26ai.sh switch-image-source company
./local-26ai.sh adb/start --19c
```

## Troubleshooting

- `404` on `/v2/`: mirror URL is not the Docker Registry API endpoint.
- `407 Access Denied`: Podman is still using proxy for `<registry-host>`.
- `x509: certificate signed by unknown authority`: internal CA is missing from the Podman machine.
- `EOF` during image pull: often a proxy, auth, or CA problem rather than an image problem.

## What Must Stay Private

- actual internal registry hosts
- exact proxy values
- CA certificate files
- authentication instructions that expose internal endpoints
- copy-paste commands containing usernames, tokens, or passwords

## Recommended Ownership

- Public repo: generic workflow and placeholder template only.
- Private repo or internal wiki: real values, screenshots, commands, and support notes.