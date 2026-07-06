#!/usr/bin/env bash
#
# Full clean reset — tears down the environment and rebuilds from scratch.
#
# Removes:  containers, volumes, .env, ords-config/databases/, ords-config/global/settings.xml,
#           apex/, apex-images/
# Keeps:   git repo, scripts/, apex-patches/, backups/, ords-config/global/standalone/ (SSL certs)
#
# Usage:
#   ./local-26ai.sh dev/reset

set -euo pipefail

cd "$(dirname "${BASH_SOURCE[0]}")/../.."

# ---------------------------------------------------------------------------
# Confirmation
# ---------------------------------------------------------------------------
echo "=== FULL RESET ==="
echo ""
echo "This will DESTROY the current environment and rebuild from scratch:"
echo "  - Stop and remove containers (local-26ai, local-26ai-ords)"
echo "  - Delete the Docker/Podman volume (oradata-26ai)"
echo "  - Delete .env, ords-config/databases/, ords-config/global/settings.xml"
echo "  - Delete apex/, apex-images/"
echo ""
echo "The following will be KEPT:"
echo "  - Git repository and all scripts"
echo "  - backups/ directory"
echo "  - apex-patches/ directory (downloaded patches)"
echo "  - SSL certificates (ords-config/global/standalone/)"
echo ""

if [ -t 0 ]; then
  read -r -p "Are you sure? Type YES to continue: " answer
  if [ "$answer" != "YES" ]; then
    echo "Aborted."
    exit 0
  fi
else
  echo "(non-interactive mode — proceeding without confirmation)"
fi

echo ""

# ---------------------------------------------------------------------------
# Detect container CLI (minimal detection, since .env may not exist yet)
# ---------------------------------------------------------------------------
if [ -n "${CONTAINER_CLI:-}" ]; then
  : # already set
elif command -v docker &>/dev/null && docker info &>/dev/null 2>&1; then
  CONTAINER_CLI="docker"
elif command -v podman &>/dev/null; then
  CONTAINER_CLI="podman"
else
  echo "Error: neither 'docker' nor 'podman' found"
  exit 1
fi

# Detect compose command
if $CONTAINER_CLI compose version &>/dev/null 2>&1; then
  DOCKER_COMPOSE="$CONTAINER_CLI compose"
elif command -v docker-compose &>/dev/null; then
  DOCKER_COMPOSE="docker-compose"
elif command -v podman-compose &>/dev/null; then
  DOCKER_COMPOSE="podman-compose"
else
  echo "Error: no compose command found"
  exit 1
fi

echo "Using: $CONTAINER_CLI / $DOCKER_COMPOSE"

# ---------------------------------------------------------------------------
# 1. Stop and remove containers
# ---------------------------------------------------------------------------
echo ""
echo "=== Stopping and removing containers ==="
$DOCKER_COMPOSE -f docker-compose.yml down 2>/dev/null || true

# Remove containers explicitly in case compose down missed them
$CONTAINER_CLI rm -f local-26ai 2>/dev/null || true
$CONTAINER_CLI rm -f local-26ai-ords 2>/dev/null || true

# ---------------------------------------------------------------------------
# 2. Remove volume
# ---------------------------------------------------------------------------
echo ""
echo "=== Removing volume ==="
$CONTAINER_CLI volume rm oradata-26ai 2>/dev/null || true

# ---------------------------------------------------------------------------
# 3. Remove generated files
# ---------------------------------------------------------------------------
echo ""
echo "=== Removing generated files ==="

rm -f .env .env.bak .env_old
echo "  removed .env"

rm -rf ./ords-config/databases
echo "  removed ords-config/databases/"

rm -f ./ords-config/global/settings.xml
echo "  removed ords-config/global/settings.xml"

rm -rf ./apex
echo "  removed apex/"

rm -rf ./apex-images
echo "  removed apex-images/"

rm -rf ./META-INF
echo "  removed META-INF/"

# ---------------------------------------------------------------------------
# 4. Recreate required directories
# ---------------------------------------------------------------------------
echo ""
echo "=== Recreating directories ==="
mkdir -p ./ords-config
mkdir -p ./apex-patches
mkdir -p ./backups/export
mkdir -p ./backups/import
echo "  done"

# ---------------------------------------------------------------------------
# 5. Run install.sh
# ---------------------------------------------------------------------------
echo ""
echo "=== Running install.sh ==="
echo ""
./install.sh
