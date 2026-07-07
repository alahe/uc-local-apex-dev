#!/usr/bin/env bash
#
# Start the Oracle ADB Free container.
#
# Usage:
#   ./local-26ai.sh adb/start              # 26ai (default)
#   ./local-26ai.sh adb/start --19c        # 19c database
#   ./local-26ai.sh adb/start --23ai       # 23ai database
#
# APEX, ORDS, and Database Actions are pre-installed and available at:
#   https://localhost:8443/ords/apex
#
# Prerequisites: Docker or Podman with at least 4 CPUs and 8GB RAM.

set -euo pipefail

cd "$(dirname "${BASH_SOURCE[0]}")/../.."

ENV_FILE=".env.adb"
COMPOSE_FILE="docker-compose.adb.yml"

# ---------------------------------------------------------------------------
# Parse arguments
# ---------------------------------------------------------------------------
ADB_IMAGE_TAG="latest-26ai"
DB_VERSION="26ai"

for arg in "$@"; do
  case "$arg" in
    --19c)   ADB_IMAGE_TAG="latest";      DB_VERSION="19c"  ;;
    --23ai)  ADB_IMAGE_TAG="latest-23ai";  DB_VERSION="23ai" ;;
    --26ai)  ADB_IMAGE_TAG="latest-26ai";  DB_VERSION="26ai" ;;
  esac
done

echo "=== Oracle ADB Free ($DB_VERSION) ==="
echo ""

# ---------------------------------------------------------------------------
# Detect container CLI
# ---------------------------------------------------------------------------
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

echo "Using: $CONTAINER_CLI / $DOCKER_COMPOSE"

# ---------------------------------------------------------------------------
# Check: main stack must not be running (port conflict)
# ---------------------------------------------------------------------------
if $CONTAINER_CLI ps --format '{{.Names}}' 2>/dev/null | grep -q "local-26ai$"; then
  echo ""
  echo "WARNING: The main DB+ORDS stack (local-26ai) is running."
  echo "Ports 1521 and 8443 will conflict."
  echo ""
  echo "Stop it first:  ./local-26ai.sh stop"
  echo "Or use:         docker compose down"
  exit 1
fi

# ---------------------------------------------------------------------------
# Generate .env.adb if it doesn't exist
# ---------------------------------------------------------------------------
if [ ! -f "$ENV_FILE" ]; then
  echo ""
  echo "Generating $ENV_FILE ..."

  # Generate a password: 12+ chars, at least 1 upper, 1 lower, 1 digit
  generate_adb_password() {
    local pw
    pw="Adb$(openssl rand -hex 6)1"
    echo "$pw"
  }

  ADB_ADMIN_PASSWORD=$(generate_adb_password)
  ADB_WALLET_PASSWORD=$(generate_adb_password)

  cat > "$ENV_FILE" <<EOF
# Oracle ADB Free container passwords
# Generated on $(date)
ADB_ADMIN_PASSWORD=$ADB_ADMIN_PASSWORD
ADB_WALLET_PASSWORD=$ADB_WALLET_PASSWORD
ADB_WORKLOAD_TYPE=ATP
ADB_IMAGE_TAG=$ADB_IMAGE_TAG
EOF

  echo "  Admin password: $ADB_ADMIN_PASSWORD"
  echo "  Wallet password: $ADB_WALLET_PASSWORD"
  echo "  Saved to $ENV_FILE"
else
  echo "Using existing $ENV_FILE"
  # Update image tag in env if different
  if grep -q "^ADB_IMAGE_TAG=" "$ENV_FILE"; then
    sed -i.bak "s/^ADB_IMAGE_TAG=.*/ADB_IMAGE_TAG=$ADB_IMAGE_TAG/" "$ENV_FILE"
    rm -f "$ENV_FILE.bak"
  else
    echo "ADB_IMAGE_TAG=$ADB_IMAGE_TAG" >> "$ENV_FILE"
  fi
fi

# Export env vars
export $(grep -v '^#' "$ENV_FILE" | xargs)

# ---------------------------------------------------------------------------
# Generate mkcert localhost certificates (if mkcert is available)
# ---------------------------------------------------------------------------
CERTS_DIR=".certs"
if [ ! -f "$CERTS_DIR/localhost.pem" ]; then
  if command -v mkcert &>/dev/null; then
    echo ""
    echo "Generating trusted localhost certificates with mkcert ..."
    mkdir -p "$CERTS_DIR"
    JAVA_HOME="" mkcert -key-file "$CERTS_DIR/localhost-key.pem" \
                        -cert-file "$CERTS_DIR/localhost.pem" \
                        localhost 127.0.0.1 ::1
    echo "  Certificates saved to $CERTS_DIR/"
  else
    echo ""
    echo "TIP: Install mkcert for trusted HTTPS (no browser warnings):"
    echo "     brew install mkcert && mkcert -install"
  fi
fi

# ---------------------------------------------------------------------------
# Pull and start
# ---------------------------------------------------------------------------
echo ""
echo "Starting ADB Free container ($DB_VERSION) ..."
$DOCKER_COMPOSE -f "$COMPOSE_FILE" --env-file "$ENV_FILE" pull
$DOCKER_COMPOSE -f "$COMPOSE_FILE" --env-file "$ENV_FILE" up -d

# ---------------------------------------------------------------------------
# Configure ORDS to use mkcert certificates (if available)
# ---------------------------------------------------------------------------
if [ -f "$CERTS_DIR/localhost.pem" ]; then
  echo ""
  echo "Configuring ORDS to use trusted localhost certificates ..."

  # Wait for ORDS config directory to be available
  RETRIES=30
  while [ $RETRIES -gt 0 ]; do
    if $CONTAINER_CLI exec local-adb-free test -f /u01/ords/global/settings.xml 2>/dev/null; then
      break
    fi
    sleep 5
    RETRIES=$((RETRIES - 1))
  done

  if [ $RETRIES -gt 0 ]; then
    # Configure ORDS to use mounted certificates
    $CONTAINER_CLI exec local-adb-free bash -c '
      ords --config /u01/ords config set standalone.https.cert /u01/ords/certs/localhost.pem 2>/dev/null
      ords --config /u01/ords config set standalone.https.cert.key /u01/ords/certs/localhost-key.pem 2>/dev/null
      ords --config /u01/ords config set standalone.https.host localhost 2>/dev/null
    ' && echo "  ORDS configured for trusted HTTPS"

    # Restart ORDS to apply certificate changes
    echo "  Restarting ORDS with trusted certificates ..."
    $CONTAINER_CLI exec local-adb-free bash -c '
      pkill -f "ords.war" 2>/dev/null || true
      sleep 3
      nohup ords --config /u01/ords serve >> /tmp/ords.log 2>&1 &
    '
    echo "  ORDS restarting (may take ~10 seconds) ..."
  else
    echo "  WARNING: Timed out waiting for ORDS config. Using default self-signed certificate."
  fi
fi

echo ""
echo "=== ADB Free container started ==="
echo ""
echo "Waiting for the database to initialize (this takes a few minutes on first run)..."
echo "Check progress with: $CONTAINER_CLI logs -f local-adb-free"
echo ""
echo "Once ready, access:"
echo "  APEX:             https://localhost:8443/ords/apex"
echo "  Database Actions: https://localhost:8443/ords/sql-developer"
echo "  DB (TLS):         localhost:1521"
echo "  DB (mTLS):        localhost:1522"
echo "  MongoDB API:      localhost:27017"
echo ""
echo "Credentials:"
echo "  Admin user:       ADMIN / (password in $ENV_FILE)"
echo ""

if [ "$DB_VERSION" = "19c" ]; then
  echo "NOTE: 19c image is AMD64 only. On Apple Silicon, this runs via emulation"
  echo "      which may be slower. Consider using Colima for better performance."
  echo ""
fi

