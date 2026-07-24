#!/usr/bin/env bash
# desc: Gracefully shut down the database, then stop the containers

set -e

source ./scripts/util/load_env.sh

echo "Gracefully stopping Oracle Database"
if ! $CONTAINER_CLI exec $CONTAINER_NAME bash -c "echo 'shutdown immediate;
exit' | sqlplus / as sysdba && exit"; then
  echo "Warning: graceful database shutdown step failed (container may already be stopped, or exec is temporarily unavailable). Continuing to stop containers anyway." >&2
fi

echo "Stopping Containers"
$DOCKER_COMPOSE -f docker-compose.yml stop
