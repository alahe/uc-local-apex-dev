#!/usr/bin/env bash
# desc: Install a local registry CA certificate into the Podman machine trust store

set -euo pipefail

cd "$(dirname "${BASH_SOURCE[0]}")/.."

DEFAULT_CERT_PATH=".certs/registry/company-ca.crt"
FALLBACK_CERT_PATHS=(
  "$DEFAULT_CERT_PATH"
  ".certs/company-ca.crt"
  ".certs/company.crt"
)

# Registry host defaults to COMPANY_REGISTRY_HOST from ./company-registry.conf
# (see company-registry.conf.example) when not passed explicitly.
REGISTRY_HOST="${2:-}"
if [ -z "$REGISTRY_HOST" ] && [ -f ./company-registry.conf ]; then
  # shellcheck source=/dev/null
  source <(tr -d '\r' <./company-registry.conf)
  REGISTRY_HOST="${COMPANY_REGISTRY_HOST:-}"
fi
PODMAN_CANDIDATES=(
  "podman.exe"
  "/c/Program Files/RedHat/Podman/podman.exe"
  "/c/Program Files/Podman/podman.exe"
  "/mnt/c/Program Files/RedHat/Podman/podman.exe"
  "/mnt/c/Program Files/Podman/podman.exe"
  "podman"
)

resolve_cert_path() {
  local candidate

  if [ -n "${1:-}" ]; then
    printf '%s\n' "$1"
    return 0
  fi

  for candidate in "${FALLBACK_CERT_PATHS[@]}"; do
    if [ -f "$candidate" ]; then
      printf '%s\n' "$candidate"
      return 0
    fi
  done

  printf '%s\n' "$DEFAULT_CERT_PATH"
}

resolve_machine_name() {
  local listed_names
  local listed_count
  local current_name

  if [ -n "${PODMAN_MACHINE_NAME:-}" ]; then
    printf '%s\n' "$PODMAN_MACHINE_NAME"
    return 0
  fi

  current_name=$($PODMAN_BIN machine info --format '{{.Host.CurrentMachine}}' 2>/dev/null || true)
  current_name="${current_name%\*}"
  current_name="${current_name%% }"
  if [ -n "$current_name" ] && [ "$current_name" != "podman-machine-default" ]; then
    printf '%s\n' "$current_name"
    return 0
  fi

  listed_names=$($PODMAN_BIN machine list --format '{{.Name}}' 2>/dev/null || true)
  listed_count=$(printf '%s\n' "$listed_names" | sed '/^$/d' | wc -l | tr -d ' ')

  if [ "$listed_count" = "1" ]; then
    printf '%s\n' "$listed_names" | sed -n '/./{p;q;}' | sed 's/\*$//; s/[[:space:]]*$//'
    return 0
  fi

  current_name=$($PODMAN_BIN machine list 2>/dev/null | awk 'NR > 1 && $1 ~ /^\*/ {print $2; exit}')
  current_name="${current_name%\*}"
  current_name="${current_name%% }"
  if [ -n "$current_name" ]; then
    printf '%s\n' "$current_name"
    return 0
  fi

  printf '%s\n' ""
}

resolve_podman_cmd() {
  local candidate

  if [ -n "${PODMAN_BIN:-}" ]; then
    printf '%s\n' "$PODMAN_BIN"
    return 0
  fi

  for candidate in "${PODMAN_CANDIDATES[@]}"; do
    if command -v "$candidate" >/dev/null 2>&1; then
      printf '%s\n' "$candidate"
      return 0
    fi

    if [ -x "$candidate" ]; then
      printf '%s\n' "$candidate"
      return 0
    fi
  done

  printf '%s\n' "podman"
}

CERT_PATH=$(resolve_cert_path "${1:-}")
PODMAN_BIN=$(resolve_podman_cmd)

usage() {
  cat <<USAGE
Usage:
  ./local-26ai.sh install-registry-ca [cert-path] [registry-host]

Defaults:
  cert-path:     $DEFAULT_CERT_PATH
  registry-host: read from COMPANY_REGISTRY_HOST in ./company-registry.conf if not given

Example:
  ./local-26ai.sh install-registry-ca
  ./local-26ai.sh install-registry-ca .certs/company.crt
  ./local-26ai.sh install-registry-ca .certs/registry/company-ca.crt <registry-host>:443
USAGE
}

if [ "${1:-}" = "--help" ] || [ "${1:-}" = "-h" ]; then
  usage
  exit 0
fi

if ! command -v "$PODMAN_BIN" >/dev/null 2>&1 && [ ! -x "$PODMAN_BIN" ]; then
  echo "Error: podman is required for install-registry-ca"
  exit 1
fi

if [ ! -f "$CERT_PATH" ]; then
  echo "Error: certificate file not found: $CERT_PATH"
  echo ""
  echo "Recommended location for local use: $DEFAULT_CERT_PATH"
  echo "Also checked: .certs/company-ca.crt and .certs/company.crt"
  exit 1
fi

if [ -z "$REGISTRY_HOST" ]; then
  echo "Error: registry host not specified."
  echo "Pass it as the second argument, or set COMPANY_REGISTRY_HOST in ./company-registry.conf (copy company-registry.conf.example)."
  exit 1
fi

PODMAN_MACHINE_NAME=$(resolve_machine_name)

REMOTE_CERT_DIR="/etc/containers/certs.d/$REGISTRY_HOST"
REMOTE_TMP_CERT="/tmp/uc-local-apex-dev-registry-ca.crt"

PODMAN_MACHINE_SSH=("$PODMAN_BIN" machine ssh)
if [ -n "$PODMAN_MACHINE_NAME" ]; then
  PODMAN_MACHINE_SSH+=("$PODMAN_MACHINE_NAME")
fi

echo "Installing registry CA for $REGISTRY_HOST"
echo "  Source file:  $CERT_PATH"
echo "  Podman CLI:   $PODMAN_BIN"
echo "  Podman VM:    ${PODMAN_MACHINE_NAME:-<current>}"

if [ -z "$PODMAN_MACHINE_NAME" ]; then
  echo "Warning: could not resolve an explicit Podman machine name; falling back to Podman current/default selection."
fi

"${PODMAN_MACHINE_SSH[@]}" "cat > '$REMOTE_TMP_CERT'" < "$CERT_PATH"
"${PODMAN_MACHINE_SSH[@]}" "sudo mkdir -p '$REMOTE_CERT_DIR' && sudo mv '$REMOTE_TMP_CERT' '$REMOTE_CERT_DIR/ca.crt' && sudo chmod 644 '$REMOTE_CERT_DIR/ca.crt'"

echo ""
echo "Installed CA certificate to $REMOTE_CERT_DIR/ca.crt"
echo "Retry your pull/start command next."