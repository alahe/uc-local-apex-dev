#!/usr/bin/env bash
# desc: One command: ensure Podman is running, install registry CA if present, switch image source, and start ADB Free
#
# Wraps the manual steps documented in readme.md's enterprise mirror section
# into a single command:
#
#   1. Ensure a Podman machine exists and is running (initializes one if
#      none exists yet).
#   2. Install the local registry CA certificate into the Podman machine's
#      trust store, if a certificate file is present under .certs/.
#   3. Switch the project's image source profile (oracle/company), if given
#      as the first argument.
#   4. Start the ADB Free container (scripts/adb/start.sh), forwarding any
#      remaining arguments (--23ai, --tag <tag>, etc.).
#
# Usage:
#   ./local-26ai.sh adb/bootstrap                        # use existing image source
#   ./local-26ai.sh adb/bootstrap oracle                 # switch to oracle profile, then start
#   ./local-26ai.sh adb/bootstrap company                # switch to company profile, then start
#   ./local-26ai.sh adb/bootstrap company --23ai          # switch profile + pass options to adb/start
#   ./local-26ai.sh adb/bootstrap -- --tag latest-26ai    # keep current profile, forward options
#
# Safe to re-run: every step is a no-op when already satisfied.

set -euo pipefail

cd "$(dirname "${BASH_SOURCE[0]}")/../.."

PODMAN_CANDIDATES=(
  "podman.exe"
  "/c/Program Files/RedHat/Podman/podman.exe"
  "/c/Program Files/Podman/podman.exe"
  "/mnt/c/Program Files/RedHat/Podman/podman.exe"
  "/mnt/c/Program Files/Podman/podman.exe"
  "podman"
)

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

usage() {
  cat <<'USAGE'
Usage:
  ./local-26ai.sh adb/bootstrap [oracle|company] [adb/start options...]

Examples:
  ./local-26ai.sh adb/bootstrap
  ./local-26ai.sh adb/bootstrap oracle
  ./local-26ai.sh adb/bootstrap company
  ./local-26ai.sh adb/bootstrap company --23ai
  ./local-26ai.sh adb/bootstrap -- --tag latest-26ai

Steps performed:
  1. Ensure a Podman machine exists and is running.
  2. Install the local registry CA certificate, if present under .certs/.
  3. Switch image source profile (oracle/company), if given.
  4. Start ADB Free (scripts/adb/start.sh), forwarding remaining options.
USAGE
}

if [ "${1:-}" = "--help" ] || [ "${1:-}" = "-h" ]; then
  usage
  exit 0
fi

if [ "${1:-}" = "--" ]; then
  shift
fi

PODMAN_BIN=$(resolve_podman_cmd)

if ! command -v "$PODMAN_BIN" >/dev/null 2>&1 && [ ! -x "$PODMAN_BIN" ]; then
  echo "Error: podman is required. Install Podman Desktop or the Podman CLI first."
  exit 1
fi

# ---------------------------------------------------------------------------
# 1. Ensure a Podman machine exists and is running
# ---------------------------------------------------------------------------
echo "=== Step 1/4: Podman machine ==="

MACHINE_LIST=$("$PODMAN_BIN" machine list --format '{{.Name}} {{.Running}}' 2>/dev/null || true)

if [ -z "$MACHINE_LIST" ]; then
  echo "No Podman machine found. Initializing one ..."
  "$PODMAN_BIN" machine init --memory 4096 --cpus 3
  "$PODMAN_BIN" machine start
elif printf '%s\n' "$MACHINE_LIST" | grep -qi 'true'; then
  echo "Podman machine already running."
else
  echo "Starting existing Podman machine ..."
  "$PODMAN_BIN" machine start
fi
echo ""

# ---------------------------------------------------------------------------
# 2. Install registry CA certificate, if present
# ---------------------------------------------------------------------------
echo "=== Step 2/4: Registry CA certificate ==="

CERT_CANDIDATES=(
  ".certs/registry/company-ca.crt"
  ".certs/company-ca.crt"
  ".certs/company.crt"
)
CERT_FOUND=""
for candidate in "${CERT_CANDIDATES[@]}"; do
  if [ -f "$candidate" ]; then
    CERT_FOUND="$candidate"
    break
  fi
done

if [ -n "$CERT_FOUND" ]; then
  echo "Found certificate: $CERT_FOUND"
  ./local-26ai.sh install-registry-ca "$CERT_FOUND"
else
  echo "No local registry CA certificate found under .certs/ - skipping."
  echo "(Only needed for the 'company' mirror profile behind a custom CA.)"
fi
echo ""

# ---------------------------------------------------------------------------
# 3. Switch image source profile, if requested
# ---------------------------------------------------------------------------
echo "=== Step 3/4: Image source profile ==="

case "${1:-}" in
  oracle|company)
    ./local-26ai.sh switch-image-source "$1"
    shift
    ;;
  *)
    echo "Keeping existing image source."
    echo "(Pass 'oracle' or 'company' as the first argument to switch profiles.)"
    ;;
esac
echo ""

# ---------------------------------------------------------------------------
# 4. Start ADB Free
# ---------------------------------------------------------------------------
echo "=== Step 4/4: Starting ADB Free ==="
./local-26ai.sh adb/start "$@"
