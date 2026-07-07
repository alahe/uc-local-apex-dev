#!/usr/bin/env bash
#
# Stop the Oracle ADB Free container.
#
# Usage:
#   ./local-26ai.sh adb/stop

set -euo pipefail

cd "$(dirname "${BASH_SOURCE[0]}")/../.."

COMPOSE_FILE="docker-compose.adb.yml"
ENV_FILE=".env.adb"

# Detect container CLI
if [ -n "${CONTAINER_CLI:-}" ]; then
  :
elif command -v docker &>/dev/null && docker info &>/dev/null 2>&1; then
  CONTAINER_CLI="docker"
elif command -v podman &>/dev/null; then
  CONTAINER_CLI="podman"
else
  echo "Error: neither 'docker' nor 'podman' found"
  exit 1
fi

if $CONTAINER_CLI compose version &>/dev/null 2>&1; then
  DOCKER_COMPOSE="$CONTAINER_CLI compose"
elif command -v docker-compose &>/dev/null; then
  DOCKER_COMPOSE="docker-compose"
else
  echo "Error: no compose command found"
  exit 1
fi

echo "Stopping ADB Free container..."

if [ -f "$ENV_FILE" ]; then
  $DOCKER_COMPOSE -f "$COMPOSE_FILE" --env-file "$ENV_FILE" down
else
  $DOCKER_COMPOSE -f "$COMPOSE_FILE" down
fi

echo "ADB Free container stopped."
