#!/usr/bin/env bash
# desc: Clone the ADB Free data volume into a second, independently runnable branch container
#
# Creates an independent copy of the current adb-data volume (a "branch") and
# starts a second ADB Free container from that copy, on auto-selected free
# host ports, so you can keep using the original container while a snapshot
# of today's changes stays around to resume from later (or vice versa).
#
# Usage:
#   ./local-26ai.sh adb/clone <branch-name>
#   ./local-26ai.sh adb/clone <branch-name> --stop     # stop the branch container
#   ./local-26ai.sh adb/clone <branch-name> --remove   # remove the branch container + volume + state
#
# Re-running with the same <branch-name> reuses its existing container/volume
# (and starts it if stopped) instead of creating a new copy.

set -euo pipefail

cd "$(dirname "${BASH_SOURCE[0]}")/../.."

BRANCH="${1:-}"
ACTION="${2:-}"

if [ -z "$BRANCH" ] || [ "$BRANCH" = "--help" ] || [ "$BRANCH" = "-h" ]; then
  echo "Usage: ./local-26ai.sh adb/clone <branch-name> [--stop|--remove]"
  echo ""
  echo "Examples:"
  echo "  ./local-26ai.sh adb/clone before-migration        # create/start the branch"
  echo "  ./local-26ai.sh adb/clone before-migration --stop  # stop it (keeps data)"
  echo "  ./local-26ai.sh adb/clone before-migration --remove # delete it entirely"
  exit 0
fi

# Sanitize branch name for use in container/volume names (podman/docker names
# only allow [a-zA-Z0-9_.-])
BRANCH_SAFE="$(printf '%s' "$BRANCH" | tr -c 'a-zA-Z0-9_.-' '-')"

SOURCE_CONTAINER="local-adb-free"
SOURCE_VOLUME="adb-data"
CLONE_CONTAINER="local-adb-free-${BRANCH_SAFE}"
CLONE_VOLUME="adb-data-${BRANCH_SAFE}"
STATE_DIR=".certs/adb-clones"
STATE_FILE="$STATE_DIR/${BRANCH_SAFE}.env"

# ---------------------------------------------------------------------------
# Detect container CLI (same pattern as adb/start.sh)
# ---------------------------------------------------------------------------
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

# ---------------------------------------------------------------------------
# --stop / --remove
# ---------------------------------------------------------------------------
if [ "$ACTION" = "--stop" ]; then
  echo "Stopping branch '$BRANCH' ($CLONE_CONTAINER) ..."
  $CONTAINER_CLI stop "$CLONE_CONTAINER"
  exit 0
fi

if [ "$ACTION" = "--remove" ]; then
  echo "Removing branch '$BRANCH' ($CLONE_CONTAINER, $CLONE_VOLUME) ..."
  $CONTAINER_CLI rm -f "$CLONE_CONTAINER" >/dev/null 2>&1 || true
  $CONTAINER_CLI volume rm "$CLONE_VOLUME" >/dev/null 2>&1 || true
  rm -f "$STATE_FILE"
  echo "Done."
  exit 0
fi

mkdir -p "$STATE_DIR"

if [ -f "$STATE_FILE" ]; then
  echo "Branch '$BRANCH' already exists — reusing its volume/ports."
  # shellcheck disable=SC1090
  source "$STATE_FILE"
else
  echo "Creating branch '$BRANCH' from a snapshot of the current $SOURCE_VOLUME volume ..."

  if ! $CONTAINER_CLI volume exists "$SOURCE_VOLUME" 2>/dev/null; then
    echo "Error: source volume '$SOURCE_VOLUME' does not exist — start ADB Free first (adb/start)."
    exit 1
  fi

  if $CONTAINER_CLI volume exists "$CLONE_VOLUME" 2>/dev/null; then
    echo "Error: volume '$CLONE_VOLUME' already exists but no state file was found at $STATE_FILE."
    echo "Remove it manually first if you want to recreate this branch:"
    echo "  $CONTAINER_CLI volume rm $CLONE_VOLUME"
    exit 1
  fi

  # Stop the source container gracefully before copying, so we don't clone a
  # database mid-write (avoids corruption on the copy). It is restarted
  # right after the copy finishes.
  SOURCE_WAS_RUNNING=false
  if [ -n "$($CONTAINER_CLI ps --filter name="^${SOURCE_CONTAINER}$" --filter status=running -q 2>/dev/null)" ]; then
    SOURCE_WAS_RUNNING=true
    echo "  Stopping $SOURCE_CONTAINER to take a consistent snapshot ..."
    $CONTAINER_CLI stop "$SOURCE_CONTAINER" >/dev/null
  fi

  echo "  Copying $SOURCE_VOLUME -> $CLONE_VOLUME ..."
  $CONTAINER_CLI volume create "$CLONE_VOLUME" >/dev/null
  $CONTAINER_CLI run --rm \
    -v "$SOURCE_VOLUME:/from:ro" \
    -v "$CLONE_VOLUME:/to" \
    docker.io/library/alpine:latest \
    sh -c "cp -a /from/. /to/"

  if [ "$SOURCE_WAS_RUNNING" = true ]; then
    echo "  Restarting $SOURCE_CONTAINER ..."
    $CONTAINER_CLI start "$SOURCE_CONTAINER" >/dev/null
  fi

  # ---------------------------------------------------------------------
  # Pick 4 free host ports (TLS, mTLS, HTTPS, MongoDB) for the branch.
  # Deterministic-but-verified: derive a starting point from the branch
  # name so re-creating the same branch tends to land on the same ports,
  # but every candidate is actually re-checked against both real listening
  # sockets and other containers' published ports before being accepted.
  # ---------------------------------------------------------------------
  port_in_use() {
    (exec 3<>"/dev/tcp/127.0.0.1/$1") 2>/dev/null && exec 3>&- 2>/dev/null
  }
  next_free_port() {
    local port="$1"
    while port_in_use "$port" || $CONTAINER_CLI ps -a --format '{{.Ports}}' 2>/dev/null | grep -q ":${port}->"; do
      port=$((port + 1))
    done
    echo "$port"
  }

  hash=$(printf '%s' "$BRANCH_SAFE" | cksum | cut -d' ' -f1)
  base=$((20000 + (hash % 400) * 10))

  DB_TLS_PORT=$(next_free_port "$base")
  DB_MTLS_PORT=$(next_free_port $((DB_TLS_PORT + 1)))
  HTTPS_PORT=$(next_free_port $((DB_MTLS_PORT + 1)))
  MONGO_PORT=$(next_free_port $((HTTPS_PORT + 1)))

  cat >"$STATE_FILE" <<EOF
CLONE_CONTAINER=$CLONE_CONTAINER
CLONE_VOLUME=$CLONE_VOLUME
DB_TLS_PORT=$DB_TLS_PORT
DB_MTLS_PORT=$DB_MTLS_PORT
HTTPS_PORT=$HTTPS_PORT
MONGO_PORT=$MONGO_PORT
EOF
  echo "  Assigned ports: TLS=$DB_TLS_PORT mTLS=$DB_MTLS_PORT HTTPS=$HTTPS_PORT Mongo=$MONGO_PORT"
fi

# ---------------------------------------------------------------------------
# Start (or resume) the branch container
# ---------------------------------------------------------------------------
ENV_FILE=".env.adb"
if [ -f "$ENV_FILE" ]; then
  export $(grep -v '^#' "$ENV_FILE" | tr -d '\r' | xargs)
fi

CERTS_DIR=".certs"
mkdir -p "$CERTS_DIR"
CERTS_DIR_ABS="$(cd "$CERTS_DIR" && pwd)"
ADB_IMAGE="${ADB_IMAGE_REPO}/${ADB_IMAGE_PATH:-database/adb-free}:${ADB_IMAGE_TAG:-latest-26ai}"

if [ -n "$($CONTAINER_CLI ps -a --filter name="^${CLONE_CONTAINER}$" -q 2>/dev/null)" ]; then
  echo "Starting existing branch container $CLONE_CONTAINER ..."
  $CONTAINER_CLI start "$CLONE_CONTAINER" >/dev/null
else
  echo "Starting branch container $CLONE_CONTAINER ..."

  HEALTHCHECK_FLAGS=()
  LOG_DRIVER_FLAGS=()
  if grep -qi microsoft /proc/version 2>/dev/null; then
    HEALTHCHECK_FLAGS=(--no-healthcheck)
    if [ "$CONTAINER_CLI" = "podman" ]; then
      LOG_DRIVER_FLAGS=(--log-driver k8s-file)
    else
      LOG_DRIVER_FLAGS=(--log-driver json-file)
    fi
  fi

  $CONTAINER_CLI run -d \
    --name "$CLONE_CONTAINER" \
    --hostname "adbfree-${BRANCH_SAFE}" \
    --restart no \
    --cap-add SYS_ADMIN \
    --device /dev/fuse \
    -p "${DB_TLS_PORT}:1522" \
    -p "${DB_MTLS_PORT}:1522" \
    -p "${HTTPS_PORT}:8443" \
    -p "${MONGO_PORT}:27017" \
    -e "WORKLOAD_TYPE=${ADB_WORKLOAD_TYPE:-ATP}" \
    -e "WALLET_PASSWORD=${ADB_WALLET_PASSWORD}" \
    -e "ADMIN_PASSWORD=${ADB_ADMIN_PASSWORD}" \
    -v "${CLONE_VOLUME}:/u01" \
    -v "$CERTS_DIR_ABS:/u01/ords/certs:ro" \
    "${HEALTHCHECK_FLAGS[@]}" \
    "${LOG_DRIVER_FLAGS[@]}" \
    "$ADB_IMAGE"
fi

# ---------------------------------------------------------------------------
# Configure ORDS to use mkcert certificates (if available), same as adb/start.sh
# ---------------------------------------------------------------------------
if [ -f "$CERTS_DIR/localhost.pem" ]; then
  echo ""
  echo "Configuring ORDS to use trusted localhost certificates ..."

  RETRIES=30
  while [ $RETRIES -gt 0 ]; do
    if $CONTAINER_CLI exec "$CLONE_CONTAINER" test -f /u01/ords/global/settings.xml 2>/dev/null; then
      break
    fi
    sleep 5
    RETRIES=$((RETRIES - 1))
  done

  if [ $RETRIES -gt 0 ]; then
    $CONTAINER_CLI exec "$CLONE_CONTAINER" bash -c '
      ords --config /u01/ords config set standalone.https.cert /u01/ords/certs/localhost.pem 2>/dev/null
      ords --config /u01/ords config set standalone.https.cert.key /u01/ords/certs/localhost-key.pem 2>/dev/null
      ords --config /u01/ords config set standalone.https.host localhost 2>/dev/null
    ' && echo "  ORDS configured for trusted HTTPS"

    # See adb/start.sh for why the pkill pattern is written as "[o]rds.war".
    $CONTAINER_CLI exec "$CLONE_CONTAINER" bash -c '
      pkill -f "[o]rds.war" 2>/dev/null || true
      sleep 3
      nohup ords --config /u01/ords serve </dev/null >> /tmp/ords.log 2>&1 &
      disown
    '
    echo "  ORDS restarting (may take ~10 seconds) ..."
  else
    echo "  WARNING: Timed out waiting for ORDS config. Using default self-signed certificate."
  fi
fi

# ---------------------------------------------------------------------------
# Wait for readiness
# ---------------------------------------------------------------------------
echo ""
echo "=== Branch '$BRANCH' container started ==="
echo ""
echo "Waiting for the database and APEX/ORDS to become ready (this takes a few minutes on first run) ..."
echo "  (Live logs: $CONTAINER_CLI logs -f $CLONE_CONTAINER)"
echo ""

READY_URL="https://localhost:${HTTPS_PORT}/ords/apex"
MAX_WAIT_SECONDS=1800
POLL_INTERVAL=15
elapsed=0
is_ready=false

if command -v curl &>/dev/null; then
  while [ "$elapsed" -lt "$MAX_WAIT_SECONDS" ]; do
    if [ -z "$($CONTAINER_CLI ps --filter name="^${CLONE_CONTAINER}$" --filter status=running -q 2>/dev/null)" ]; then
      echo ""
      echo "ERROR: $CLONE_CONTAINER stopped unexpectedly. Check logs with: $CONTAINER_CLI logs $CLONE_CONTAINER"
      exit 1
    fi

    http_code="$(curl -sk -o /dev/null -w '%{http_code}' --max-time 5 "$READY_URL" 2>/dev/null || true)"
    if [ "$http_code" = "200" ] || [ "$http_code" = "302" ] || [ "$http_code" = "301" ]; then
      is_ready=true
      break
    fi

    echo "  [$(date '+%H:%M:%S')] Still initializing (elapsed ${elapsed}s, last HTTP status: ${http_code:-none}) ..."
    sleep "$POLL_INTERVAL"
    elapsed=$((elapsed + POLL_INTERVAL))
  done
else
  echo "  (curl not found on host - skipping automatic readiness check)"
fi

echo ""
if [ "$is_ready" = true ]; then
  echo "=== Ready! Branch '$BRANCH' is responding (after ~${elapsed}s) ==="
else
  echo "=== Branch container is running, but readiness could not be confirmed automatically ==="
  echo "It may still be initializing. Check progress with: $CONTAINER_CLI logs -f $CLONE_CONTAINER"
fi
echo ""
echo "Access:"
echo "  APEX:             https://localhost:${HTTPS_PORT}/ords/apex"
echo "  Database Actions: https://localhost:${HTTPS_PORT}/ords/sql-developer"
echo "  DB (TLS):         localhost:${DB_TLS_PORT}"
echo "  DB (mTLS):        localhost:${DB_MTLS_PORT}"
echo "  MongoDB API:      localhost:${MONGO_PORT}"
echo ""
echo "Credentials:"
echo "  Admin user:       ADMIN / (same password as in $ENV_FILE)"
echo ""
echo "Manage this branch:"
echo "  Stop it:   ./local-26ai.sh adb/clone $BRANCH --stop"
echo "  Resume it: ./local-26ai.sh adb/clone $BRANCH"
echo "  Delete it: ./local-26ai.sh adb/clone $BRANCH --remove"
