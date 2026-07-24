#!/usr/bin/env bash
# desc: Switch image source profile (oracle/company) for DB, ORDS, and ADB

set -euo pipefail

cd "$(dirname "${BASH_SOURCE[0]}")/.."

PROFILE="${1:-}"
if [ -z "$PROFILE" ]; then
  echo "Usage: ./local-26ai.sh switch-image-source <oracle|company>"
  exit 1
fi

case "$PROFILE" in
  oracle)
    DB_IMAGE_REPO="container-registry.oracle.com"
    ORDS_IMAGE_REPO="container-registry.oracle.com"
    ADB_IMAGE_REPO="container-registry.oracle.com"
    ADB_IMAGE_PATH="database/adb-free"
    ;;
  company)
    source ./scripts/util/load_company_registry.sh
    if ! load_company_registry_conf; then
      exit 1
    fi
    DB_IMAGE_REPO="$COMPANY_IMAGE_REPO"
    ORDS_IMAGE_REPO="$COMPANY_IMAGE_REPO"
    ADB_IMAGE_REPO="$COMPANY_IMAGE_REPO"
    ADB_IMAGE_PATH="$COMPANY_ADB_IMAGE_PATH"
    ;;
  *)
    echo "Invalid profile '$PROFILE'. Use oracle or company."
    exit 1
    ;;
esac

set_or_append_key() {
  local file="$1"
  local key="$2"
  local value="$3"

  if grep -qE "^${key}=" "$file"; then
    sed -i.bak "s#^${key}=.*#${key}=${value}#" "$file"
    rm -f "$file.bak"
  else
    echo "${key}=${value}" >> "$file"
  fi
}

if [ ! -f .env ]; then
  echo ".env not found. Generating it with IMAGE_SOURCE=$PROFILE ..."
  IMAGE_SOURCE="$PROFILE" ./setup.sh
fi

set_or_append_key .env IMAGE_SOURCE "\"$PROFILE\""
set_or_append_key .env DB_IMAGE_REPO "\"$DB_IMAGE_REPO\""
set_or_append_key .env ORDS_IMAGE_REPO "\"$ORDS_IMAGE_REPO\""

echo "Updated .env image settings to '$PROFILE'."

if [ -f .env.adb ]; then
  set_or_append_key .env.adb IMAGE_SOURCE "$PROFILE"
  set_or_append_key .env.adb ADB_IMAGE_REPO "$ADB_IMAGE_REPO"
  set_or_append_key .env.adb ADB_IMAGE_PATH "$ADB_IMAGE_PATH"
  echo "Updated .env.adb image settings to '$PROFILE'."
else
  echo ".env.adb not found. It will be created on first adb/start using IMAGE_SOURCE from .env."
fi

echo "Done. Next pull/start will use '$PROFILE' image repositories."
