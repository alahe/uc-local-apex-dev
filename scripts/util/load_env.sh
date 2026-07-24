#!/usr/bin/env bash

if [ ! -f .env ]; then
  echo "Error: env file not found"
  exit 1
fi

# check if .env is in the current directory or in the parent directory
# Strip any CRLF line endings first: a CRLF-tainted .env (e.g. edited on
# Windows) leaves a trailing \r on every exported value, which can break
# downstream tools that consume these vars.
export $(grep -v '^#' .env | tr -d '\r' | xargs)

echo "loaded .env file"

# Wrap SQLcl so non-interactive (heredoc/pipe) calls don't fail with
# "Unable to create a terminal". JLine can't allocate a real terminal when
# stdin isn't a TTY (varies by SQLcl/JLine version); TERM=dumb makes it fall
# back silently. Interactive sessions keep their real TERM so line editing,
# history and colors still work.
sql() {
  if [ -t 0 ]; then
    command sql "$@"
  else
    TERM=dumb command sql "$@"
  fi
}
export -f sql

# Detect container CLI (prefer docker, fall back to podman).
# Can be overridden: CONTAINER_CLI=podman ./install.sh
if [ -n "${CONTAINER_CLI:-}" ]; then
  : # already set by user — respect it
elif command -v docker &>/dev/null && docker info &>/dev/null 2>&1; then
  CONTAINER_CLI="docker"
elif command -v podman &>/dev/null; then
  CONTAINER_CLI="podman"
else
  echo "Error: neither 'docker' nor 'podman' found"
  exit 1
fi
export CONTAINER_CLI

# Detect compose command (prefer native subcommand, fall back to standalone)
if $CONTAINER_CLI compose version &>/dev/null 2>&1; then
  DOCKER_COMPOSE="$CONTAINER_CLI compose"
elif command -v docker-compose &>/dev/null; then
  DOCKER_COMPOSE="docker-compose"
elif command -v podman-compose &>/dev/null; then
  DOCKER_COMPOSE="podman-compose"
else
  echo "Error: no compose command found (tried: $CONTAINER_CLI compose, docker-compose, podman-compose)"
  exit 1
fi
