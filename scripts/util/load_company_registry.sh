#!/usr/bin/env bash
#
# Sources ./company-registry.conf (or $COMPANY_REGISTRY_CONF) and exports
# COMPANY_IMAGE_REPO / COMPANY_REGISTRY_HOST / COMPANY_ADB_IMAGE_PATH.
#
# Usage (from a script that has already `cd`ed to the repo root):
#   source ./scripts/util/load_company_registry.sh
#   if ! load_company_registry_conf; then
#     exit 1
#   fi

load_company_registry_conf() {
  local conf_file="${COMPANY_REGISTRY_CONF:-./company-registry.conf}"

  if [ ! -f "$conf_file" ]; then
    echo "Error: IMAGE_SOURCE=company requires $conf_file." >&2
    echo "Copy company-registry.conf.example to $conf_file and fill in your registry details." >&2
    return 1
  fi

  # shellcheck source=/dev/null
  source <(tr -d '\r' <"$conf_file")

  if [ -z "${COMPANY_IMAGE_REPO:-}" ]; then
    echo "Error: COMPANY_IMAGE_REPO not set in $conf_file." >&2
    return 1
  fi

  COMPANY_REGISTRY_HOST="${COMPANY_REGISTRY_HOST:-${COMPANY_IMAGE_REPO}:443}"
  COMPANY_ADB_IMAGE_PATH="${COMPANY_ADB_IMAGE_PATH:-database/adb-free}"
}
