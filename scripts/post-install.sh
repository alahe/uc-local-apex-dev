#!/usr/bin/env bash
#
# Reads post-install.conf and creates users/workspaces + ORDS pools.
# Called automatically by install.sh if post-install.conf exists.
# Safe to re-run — existing users are skipped.
#
# Usage:
#   ./scripts/post-install.sh                 # reads post-install.conf
#   POST_INSTALL_CONF=my.conf ./scripts/post-install.sh  # custom file

set -euo pipefail

CONF_FILE="${POST_INSTALL_CONF:-./post-install.conf}"

if [ ! -f "$CONF_FILE" ]; then
  echo "No post-install.conf found — skipping post-install configuration."
  exit 0
fi

echo "Reading configuration from $CONF_FILE ..."

# Source the config (defines USERS and ORDS_POOLS arrays)
# shellcheck source=post-install.conf.example
source "$CONF_FILE"

# Ensure arrays are defined (default to empty)
USERS=("${USERS[@]:-}")
ORDS_POOLS=("${ORDS_POOLS[@]:-}")

source ./scripts/util/load_env.sh
source ./scripts/util/user-exists-in-db.sh

# ---------------------------------------------------------------------------
# 1. Create users and workspaces
# ---------------------------------------------------------------------------
users_created=0
users_skipped=0

for username in "${USERS[@]}"; do
  # Skip empty entries
  [ -z "$username" ] && continue

  username_upper=$(echo "$username" | tr '[:lower:]' '[:upper:]')

  if user_exists_in_db "$username"; then
    echo "  ⏭  User $username_upper already exists — skipping."
    users_skipped=$((users_skipped + 1))
  else
    echo "  ➕ Creating user: $username ..."
    ./scripts/create-user.sh "$username"
    users_created=$((users_created + 1))
  fi
done

# ---------------------------------------------------------------------------
# 2. Add ORDS connection pools
# ---------------------------------------------------------------------------
pools_created=0
pools_skipped=0

for pool_entry in "${ORDS_POOLS[@]}"; do
  # Skip empty entries
  [ -z "$pool_entry" ] && continue

  # Parse: pool_name|db_host|db_port|db_service
  IFS='|' read -r pool_name db_host db_port db_service <<< "$pool_entry"

  if [ -z "$pool_name" ] || [ -z "$db_host" ] || [ -z "$db_port" ] || [ -z "$db_service" ]; then
    echo "  ⚠  Invalid ORDS pool entry: $pool_entry (expected: name|host|port|service)"
    continue
  fi

  # Check if pool already exists in ORDS config
  if $CONTAINER_CLI exec local-26ai-ords bash -c \
       "ords --config /etc/ords/config config list --db-pool $pool_name" &>/dev/null 2>&1; then
    echo "  ⏭  ORDS pool '$pool_name' already exists — skipping."
    pools_skipped=$((pools_skipped + 1))
  else
    echo "  ➕ Adding ORDS pool: $pool_name ($db_host:$db_port/$db_service) ..."

    $CONTAINER_CLI exec local-26ai-ords bash -c "
      ords --config /etc/ords/config config \
        --db-pool $pool_name \
        set db.hostname $db_host && \
      ords --config /etc/ords/config config \
        --db-pool $pool_name \
        set db.port $db_port && \
      ords --config /etc/ords/config config \
        --db-pool $pool_name \
        set db.servicename $db_service && \
      ords --config /etc/ords/config config \
        --db-pool $pool_name \
        set db.username ORDS_PUBLIC_USER
    "

    pools_created=$((pools_created + 1))
    echo "    Pool '$pool_name' added. Restart ORDS to activate: ./local-26ai.sh stop && ./local-26ai.sh start"
  fi
done

# ---------------------------------------------------------------------------
# Summary
# ---------------------------------------------------------------------------
echo ""
echo "Post-install complete:"
echo "  Users:      $users_created created, $users_skipped skipped"
echo "  ORDS pools: $pools_created created, $pools_skipped skipped"

if [ "$pools_created" -gt 0 ]; then
  echo ""
  echo "Note: Restart ORDS to activate new connection pools."
fi
