#!/usr/bin/env bash
# desc: Stop the Oracle ADB Free container
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
DOCKER_INFO_OUTPUT=""
if command -v docker &>/dev/null; then
  DOCKER_INFO_OUTPUT=$(docker info 2>&1 || true)
fi

if [ -n "${CONTAINER_CLI:-}" ]; then
  :
elif command -v podman &>/dev/null && printf '%s' "$DOCKER_INFO_OUTPUT" | grep -qi 'podman'; then
  CONTAINER_CLI="podman"
elif command -v docker &>/dev/null && [ -n "$DOCKER_INFO_OUTPUT" ] && ! printf '%s' "$DOCKER_INFO_OUTPUT" | grep -qi 'podman'; then
  CONTAINER_CLI="docker"
elif command -v podman &>/dev/null; then
  CONTAINER_CLI="podman"
else
  echo "Error: neither 'docker' nor 'podman' found"
  exit 1
fi

USE_COMPOSE=true
if $CONTAINER_CLI compose version &>/dev/null 2>&1; then
  DOCKER_COMPOSE="$CONTAINER_CLI compose"
elif [ "$CONTAINER_CLI" = "docker" ] && command -v docker-compose &>/dev/null; then
  DOCKER_COMPOSE="docker-compose"
else
  USE_COMPOSE=false
fi

echo "Stopping ADB Free container..."

if [ "$USE_COMPOSE" = true ] && [ -f "$ENV_FILE" ]; then
  $DOCKER_COMPOSE -f "$COMPOSE_FILE" --env-file "$ENV_FILE" down
elif [ "$USE_COMPOSE" = true ]; then
  $DOCKER_COMPOSE -f "$COMPOSE_FILE" down
else
  $CONTAINER_CLI stop local-adb-free >/dev/null 2>&1 || true
  $CONTAINER_CLI rm local-adb-free >/dev/null 2>&1 || true
fi

echo "ADB Free container stopped."
