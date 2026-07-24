#!/usr/bin/env bash
# desc: Start the Oracle ADB Free container (oracle or company mirror)
#
# Start the Oracle ADB Free container.
#
# Usage:
#   ./local-26ai.sh adb/start              # 26ai (default)
#   ./local-26ai.sh adb/start --19c        # 19c database
#   ./local-26ai.sh adb/start --23ai       # 23ai database
#   ./local-26ai.sh adb/start --26ai-26.5.4.2   # specific 26ai release
#   ./local-26ai.sh adb/start --19c-26.2.4.2    # specific 19c release
#   ./local-26ai.sh adb/start --tag <image-tag> # custom image tag
#
# APEX, ORDS, and Database Actions are pre-installed and available at:
#   https://localhost:8443/ords/apex
#
# Prerequisites: Docker or Podman with at least 4 CPUs and 8GB RAM.

set -euo pipefail

cd "$(dirname "${BASH_SOURCE[0]}")/../.."

ENV_FILE=".env.adb"
COMPOSE_FILE="docker-compose.adb.yml"

# Resolve image source profile (oracle/company). Explicit env wins; otherwise
# reuse .env IMAGE_SOURCE when available.
if [ -z "${IMAGE_SOURCE:-}" ] && [ -f .env ]; then
  IMAGE_SOURCE=$(grep -E '^IMAGE_SOURCE=' .env | tail -1 | cut -d= -f2- | tr -d '"' || true)
fi
IMAGE_SOURCE="${IMAGE_SOURCE:-oracle}"

ADB_IMAGE_REPO_DEFAULT="container-registry.oracle.com"
ADB_IMAGE_PATH_DEFAULT="database/adb-free"
case "$IMAGE_SOURCE" in
  oracle)
    ;;
  company)
    source ./scripts/util/load_company_registry.sh
    if ! load_company_registry_conf; then
      exit 1
    fi
    ADB_IMAGE_REPO_DEFAULT="$COMPANY_IMAGE_REPO"
    ADB_IMAGE_PATH_DEFAULT="$COMPANY_ADB_IMAGE_PATH"
    ;;
  *)
    echo "Error: invalid IMAGE_SOURCE '$IMAGE_SOURCE' (use oracle or company)"
    exit 1
    ;;
esac

append_no_proxy_host() {
  local var_name="$1"
  local host="$2"
  local current_value="${!var_name:-}"

  case ",${current_value}," in
    *",${host},"*)
      ;;
    ,,*|,)
      printf -v "$var_name" '%s' "$host"
      export "$var_name"
      ;;
    *)
      printf -v "$var_name" '%s,%s' "$current_value" "$host"
      export "$var_name"
      ;;
  esac
}

configure_oracle_no_proxy() {
  [ "$IMAGE_SOURCE" = "oracle" ] || return 0

  append_no_proxy_host NO_PROXY "container-registry.oracle.com"
  append_no_proxy_host NO_PROXY ".objectstorage.us-phoenix-1.oraclecloud.com"
  append_no_proxy_host NO_PROXY "objectstorage.us-phoenix-1.oraclecloud.com"
  append_no_proxy_host no_proxy "container-registry.oracle.com"
  append_no_proxy_host no_proxy ".objectstorage.us-phoenix-1.oraclecloud.com"
  append_no_proxy_host no_proxy "objectstorage.us-phoenix-1.oraclecloud.com"
}

# Trust the mkcert root CA in the CURRENT USER's OS certificate store, so
# browsers stop showing "unsafe"/untrusted warnings for https://localhost.
# This only needs to happen once per Windows user profile / macOS user - the
# root CA is created once under `mkcert -CAROOT` and reused for every future
# leaf cert (including if .certs/localhost.pem later gets regenerated), so
# this call is safe (and cheap) to make on every start.sh run: it no-ops if
# the CA is already trusted, and re-adding an already-trusted cert is a
# harmless idempotent operation.
trust_mkcert_ca() {
  command -v mkcert &>/dev/null || return 0
  local caroot rootca
  caroot="$(mkcert -CAROOT 2>/dev/null)" || return 0
  rootca="$caroot/rootCA.pem"
  [ -f "$rootca" ] || return 0

  if grep -qi microsoft /proc/version 2>/dev/null && command -v certutil.exe &>/dev/null; then
    # WSL2 with Windows interop enabled: import into the Windows user's own
    # Trusted Root store via certutil.exe. "-user" avoids needing admin/UAC.
    local winpath
    winpath="$(wslpath -w "$rootca" 2>/dev/null)" || return 0
    if certutil.exe -user -addstore Root "$winpath" &>/dev/null; then
      echo "  Trusted mkcert CA in the Windows user certificate store"
    fi
  elif [ "$(uname -s)" = "Darwin" ]; then
    # macOS: mkcert -install adds the CA to the login keychain.
    mkcert -install &>/dev/null || true
  fi
}

handle_pull_failure() {
  local image_ref="$1"

  if [ "$IMAGE_SOURCE" = "oracle" ]; then
    echo ""
    echo "Oracle image pull failed from: $image_ref"
    echo "The login to container-registry.oracle.com may be valid, but the image blobs"
    echo "are downloaded from Oracle Object Storage in OCI and your network is resetting"
    echo "those connections."
    echo ""
    echo "Recommended next step: switch ADB pulls to the company mirror and retry."
    echo "Example: bash ./local-26ai.sh switch-image-source company"
    echo ""
  fi
}

# On first run, the ADB Free entrypoint downloads a seed PDB archive from
# Oracle Object Storage (objectstorage.us-phoenix-1.oraclecloud.com).
# Corporate proxies often reset that connection from WSL/Linux, while the
# same URL works fine from a Windows-native HTTP client (browser, PowerShell)
# because those transparently use the Windows system/PAC proxy and SSO.
# When running on WSL, pre-fetch the file via powershell.exe and drop it
# straight into the adb-data volume so the container's own download step
# finds it already present and skips the network call entirely.
try_prefetch_pdb_via_windows() {
  grep -qi microsoft /proc/version 2>/dev/null || return 0
  command -v powershell.exe &>/dev/null || return 0
  command -v wslpath &>/dev/null || return 0

  local workload_type pdb_name
  workload_type="${ADB_WORKLOAD_TYPE:-ATP}"
  pdb_name="MY_$(printf '%s' "$workload_type" | tr '[:lower:]' '[:upper:]').pdb"

  # The volume's files are owned by the rootless container's remapped
  # (sub-)uid, not the host user, so we can't reliably `test -f`/`mv` into it
  # directly from the host shell - use `podman cp` (namespace-aware) for
  # anything that touches the volume's contents.
  #
  # The entrypoint's download_my_container_pdb.py saves the file under
  # container_state/input.json's "archive_file_name" (e.g. "MYATP.pdb", no
  # underscore) when that file exists from a prior run - NOT under the
  # remote download filename ("MY_ATP.pdb", with underscore). Both the
  # existence probe and the final placement must use that local name,
  # otherwise the entrypoint's own os.path.exists() check never matches and
  # it re-downloads over the network regardless of what we pre-fetched.
  local probe_container probe_tmp input_json_tmp local_pdb_name
  probe_container="adb-pdb-probe-tmp"
  probe_tmp="$(mktemp)"
  input_json_tmp="$(mktemp)"
  local_pdb_name="$pdb_name"
  $CONTAINER_CLI rm -f "$probe_container" >/dev/null 2>&1 || true
  if $CONTAINER_CLI create --name "$probe_container" -v adb-data:/u01 "$ADB_IMAGE" >/dev/null 2>&1; then
    if $CONTAINER_CLI cp "$probe_container:/u01/container_state/input.json" "$input_json_tmp" >/dev/null 2>&1 && [ -s "$input_json_tmp" ]; then
      local extracted_name
      extracted_name="$(grep -oP '"archive_file_name"\s*:\s*"\K[^"]+' "$input_json_tmp" || true)"
      [ -n "$extracted_name" ] && local_pdb_name="$extracted_name"
    fi
    if $CONTAINER_CLI cp "$probe_container:/u01/data/$local_pdb_name" "$probe_tmp" >/dev/null 2>&1 && [ -s "$probe_tmp" ]; then
      $CONTAINER_CLI rm -f "$probe_container" >/dev/null 2>&1 || true
      rm -f "$probe_tmp" "$input_json_tmp"
      return 0
    fi
    $CONTAINER_CLI rm -f "$probe_container" >/dev/null 2>&1 || true
  fi
  rm -f "$probe_tmp" "$input_json_tmp"

  # Read IMAGE_TYPE/ARCH from the pulled image and the cloud service version
  # baked into it, to build the exact Object Storage URL used by the
  # image's own download_my_container_pdb.py.
  local image_env image_type arch tmp_container tmp_csv cloud_service_version
  image_env="$($CONTAINER_CLI inspect "$ADB_IMAGE" --format '{{json .Config.Env}}' 2>/dev/null)"
  image_type="$(printf '%s' "$image_env" | grep -oP 'IMAGE_TYPE=\K[^"\\]+' || true)"
  arch="$(printf '%s' "$image_env" | grep -oP 'ARCH=\K[^"\\]+' || true)"
  image_type="${image_type:-free}"
  arch="${arch:-x64}"

  tmp_container="adb-pdb-fetch-tmp"
  tmp_csv="$(mktemp)"
  $CONTAINER_CLI rm -f "$tmp_container" >/dev/null 2>&1 || true
  if ! $CONTAINER_CLI create --name "$tmp_container" "$ADB_IMAGE" >/dev/null 2>&1; then
    rm -f "$tmp_csv"
    return 0
  fi
  $CONTAINER_CLI cp "$tmp_container:/u01/cloud_service_version" "$tmp_csv" >/dev/null 2>&1
  $CONTAINER_CLI rm -f "$tmp_container" >/dev/null 2>&1 || true
  cloud_service_version="$(tr -d '\r\n' < "$tmp_csv")"
  rm -f "$tmp_csv"
  [ -n "$cloud_service_version" ] || return 0

  local url="https://objectstorage.us-phoenix-1.oraclecloud.com/n/dwcsdev/b/adb-${image_type}/o/${cloud_service_version}/${arch}/${pdb_name}"

  echo ""
  echo "Pre-fetching seed database ($pdb_name) via Windows (this can take a while) ..."

  # Use a script FILE (instead of an inline -Command string) to avoid the
  # multiple layers of shell-quoting problems that come from crossing the
  # WSL/Windows interop boundary. Corporate NTLM/Kerberos proxies require
  # explicit -ProxyUseDefaultCredentials (Invoke-WebRequest's own
  # -UseDefaultCredentials only covers the target server, not the proxy),
  # and PowerShell's Constrained Language Mode blocks dynamic proxy
  # discovery via .NET methods (e.g. [System.Net.WebRequest]::GetSystemWebProxy()).
  # A direct (no-proxy) attempt is always tried first; if your network needs
  # an explicit proxy, list it in COMPANY_PROXY_HOSTS in ./company-registry.conf
  # (comma-separated "host:port" values, see company-registry.conf.example).
  # Write the script under C:\Windows\Temp (via /mnt/c) rather than WSL's own
  # /tmp: converting a /tmp path with `wslpath -w` yields a \\wsl.localhost\...
  # UNC path, and this environment's security policy silently refuses to run
  # -File scripts from network locations (no error, just empty output).
  local win_tmp_dir="/mnt/c/Windows/Temp"
  [ -d "$win_tmp_dir" ] || win_tmp_dir="/tmp"

  local proxy_list_ps="''"
  if [ -z "${COMPANY_PROXY_HOSTS+x}" ] && [ -f ./company-registry.conf ]; then
    # shellcheck source=/dev/null
    source <(tr -d '\r' <./company-registry.conf)
  fi
  if [ -n "${COMPANY_PROXY_HOSTS:-}" ]; then
    local proxy_host proxy_entries=("''")
    IFS=',' read -ra _company_proxy_hosts <<<"$COMPANY_PROXY_HOSTS"
    for proxy_host in "${_company_proxy_hosts[@]}"; do
      proxy_host="$(printf '%s' "$proxy_host" | xargs)"
      [ -n "$proxy_host" ] && proxy_entries+=("'http://$proxy_host'")
    done
    proxy_list_ps="$(IFS=,; printf '%s' "${proxy_entries[*]}")"
  fi

  local ps1_tmp win_ps1 win_out
  ps1_tmp="$(mktemp "$win_tmp_dir/adb-fetch-pdb-XXXXXX.ps1")"
  cat > "$ps1_tmp" <<PS1EOF
\$ProgressPreference = 'SilentlyContinue'
\$dest = Join-Path \$env:TEMP '$pdb_name'
\$url = '$url'
\$proxies = @($proxy_list_ps)
\$ok = \$false
foreach (\$p in \$proxies) {
  try {
    if (\$p) {
      Invoke-WebRequest -Uri \$url -OutFile \$dest -UseBasicParsing -Proxy \$p -ProxyUseDefaultCredentials
    } else {
      Invoke-WebRequest -Uri \$url -OutFile \$dest -UseBasicParsing
    }
    \$ok = \$true
    break
  } catch {
    continue
  }
}
if (\$ok) { Write-Output "OK:\$dest" } else { Write-Output 'DOWNLOAD_FAILED' }
PS1EOF

  win_ps1="$(wslpath -w "$ps1_tmp" 2>/dev/null)"
  if [ -z "$win_ps1" ]; then
    rm -f "$ps1_tmp"
    echo "  Pre-fetch via Windows failed; falling back to the container's own download."
    return 0
  fi

  win_out="$(powershell.exe -NoProfile -ExecutionPolicy Bypass -File "$win_ps1" 2>/dev/null | tr -d '\r')"
  rm -f "$ps1_tmp"
  win_out="$(printf '%s\n' "$win_out" | grep -E '^(OK:|DOWNLOAD_FAILED$)' | tail -1)"
  win_out="${win_out#OK:}"

  if [ -z "$win_out" ] || [ "$win_out" = "DOWNLOAD_FAILED" ]; then
    echo "  Pre-fetch via Windows failed; falling back to the container's own download."
    return 0
  fi

  local wsl_path
  wsl_path="$(wslpath -u "$win_out" 2>/dev/null)"
  if [ -z "$wsl_path" ] || [ ! -f "$wsl_path" ]; then
    echo "  Pre-fetch via Windows failed; falling back to the container's own download."
    return 0
  fi

  local place_container="adb-pdb-place-tmp"
  $CONTAINER_CLI rm -f "$place_container" >/dev/null 2>&1 || true
  if $CONTAINER_CLI create --name "$place_container" -v adb-data:/u01 "$ADB_IMAGE" >/dev/null 2>&1 \
    && $CONTAINER_CLI cp "$wsl_path" "$place_container:/u01/data/$local_pdb_name" >/dev/null 2>&1; then
    echo "  Saved as /u01/data/$local_pdb_name in the adb-data volume."
    rm -f "$wsl_path"
  else
    echo "  Could not copy downloaded file into the adb-data volume; falling back to the container's own download."
  fi
  $CONTAINER_CLI rm -f "$place_container" >/dev/null 2>&1 || true
}

# ---------------------------------------------------------------------------
# Parse arguments
# ---------------------------------------------------------------------------
ADB_IMAGE_TAG="latest-26ai"
DB_VERSION="26ai"

while [ $# -gt 0 ]; do
  case "$1" in
    --19c)
      ADB_IMAGE_TAG="latest"
      DB_VERSION="19c"
      ;;
    --23ai)
      ADB_IMAGE_TAG="latest-23ai"
      DB_VERSION="23ai"
      ;;
    --26ai)
      ADB_IMAGE_TAG="latest-26ai"
      DB_VERSION="26ai"
      ;;
    --26ai-26.5.4.2)
      ADB_IMAGE_TAG="26.5.4.2-26ai"
      DB_VERSION="26ai"
      ;;
    --26ai-26.2.4.2)
      ADB_IMAGE_TAG="26.2.4.2-26ai"
      DB_VERSION="26ai"
      ;;
    --19c-26.2.4.2)
      ADB_IMAGE_TAG="26.2.4.2"
      DB_VERSION="19c"
      ;;
    --tag)
      shift
      if [ $# -eq 0 ]; then
        echo "Error: --tag requires a value"
        exit 1
      fi
      ADB_IMAGE_TAG="$1"
      case "$ADB_IMAGE_TAG" in
        latest-26ai|*-26ai)
          DB_VERSION="26ai"
          ;;
        latest-23ai|*-23ai)
          DB_VERSION="23ai"
          ;;
        latest|[0-9]*.[0-9]*.[0-9]*.[0-9]*)
          DB_VERSION="19c"
          ;;
      esac
      ;;
    --help|-h)
      cat <<'USAGE'
Usage:
  ./local-26ai.sh adb/start
  ./local-26ai.sh adb/start --19c
  ./local-26ai.sh adb/start --23ai
  ./local-26ai.sh adb/start --26ai
  ./local-26ai.sh adb/start --26ai-26.5.4.2
  ./local-26ai.sh adb/start --26ai-26.2.4.2
  ./local-26ai.sh adb/start --19c-26.2.4.2
  ./local-26ai.sh adb/start --tag <image-tag>
USAGE
      exit 0
      ;;
    *)
      echo "Error: unknown argument '$1'"
      echo "Tip: use --help to see supported options"
      exit 1
      ;;
  esac
  shift
done

echo "=== Oracle ADB Free ($DB_VERSION) ==="
echo ""

# ---------------------------------------------------------------------------
# Detect container CLI
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

USE_COMPOSE=true
if $CONTAINER_CLI compose version &>/dev/null 2>&1; then
  DOCKER_COMPOSE="$CONTAINER_CLI compose"
elif [ "$CONTAINER_CLI" = "docker" ] && command -v docker-compose &>/dev/null; then
  DOCKER_COMPOSE="docker-compose"
else
  USE_COMPOSE=false
fi

if [ "$USE_COMPOSE" = true ]; then
  echo "Using: $CONTAINER_CLI / $DOCKER_COMPOSE"
else
  echo "Using: $CONTAINER_CLI / direct run fallback"
fi

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
IMAGE_SOURCE=$IMAGE_SOURCE
ADB_IMAGE_PATH=$ADB_IMAGE_PATH_DEFAULT
ADB_IMAGE_TAG=$ADB_IMAGE_TAG
ADB_IMAGE_REPO=$ADB_IMAGE_REPO_DEFAULT
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

  if grep -q "^ADB_IMAGE_PATH=" "$ENV_FILE"; then
    sed -i.bak "s#^ADB_IMAGE_PATH=.*#ADB_IMAGE_PATH=$ADB_IMAGE_PATH_DEFAULT#" "$ENV_FILE"
    rm -f "$ENV_FILE.bak"
  else
    echo "ADB_IMAGE_PATH=$ADB_IMAGE_PATH_DEFAULT" >> "$ENV_FILE"
  fi

  if grep -q "^ADB_IMAGE_NAME=" "$ENV_FILE"; then
    sed -i.bak '/^ADB_IMAGE_NAME=/d' "$ENV_FILE"
    rm -f "$ENV_FILE.bak"
  fi

  if grep -q "^IMAGE_SOURCE=" "$ENV_FILE"; then
    sed -i.bak "s/^IMAGE_SOURCE=.*/IMAGE_SOURCE=$IMAGE_SOURCE/" "$ENV_FILE"
    rm -f "$ENV_FILE.bak"
  else
    echo "IMAGE_SOURCE=$IMAGE_SOURCE" >> "$ENV_FILE"
  fi

  if grep -q "^ADB_IMAGE_REPO=" "$ENV_FILE"; then
    sed -i.bak "s#^ADB_IMAGE_REPO=.*#ADB_IMAGE_REPO=$ADB_IMAGE_REPO_DEFAULT#" "$ENV_FILE"
    rm -f "$ENV_FILE.bak"
  else
    echo "ADB_IMAGE_REPO=$ADB_IMAGE_REPO_DEFAULT" >> "$ENV_FILE"
  fi
fi

# Export env vars
# Strip any CRLF line endings first: a CRLF-tainted .env.adb (e.g. edited on
# Windows) leaves a trailing \r on every exported value, which breaks the
# ADB Free entrypoint's validation (e.g. "DATABASE_NAME must contain only
# alphanumeric characters").
export $(grep -v '^#' "$ENV_FILE" | tr -d '\r' | xargs)
configure_oracle_no_proxy

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
    echo "     macOS:  brew install mkcert && mkcert -install"
    echo "     Linux:  download the binary from https://github.com/FiloSottile/mkcert/releases,"
    echo "             chmod +x it into /usr/local/bin/mkcert (nss-tools/mkcert -install NOT required"
    echo "             when the browser runs on a different host/OS than mkcert, e.g. WSL2)"
  fi
fi
trust_mkcert_ca

# ---------------------------------------------------------------------------
# Pull and start
# ---------------------------------------------------------------------------
echo ""
echo "Starting ADB Free container ($DB_VERSION) ..."
if [ "$USE_COMPOSE" = true ]; then
  if ! $DOCKER_COMPOSE -f "$COMPOSE_FILE" --env-file "$ENV_FILE" pull; then
    handle_pull_failure "${ADB_IMAGE_REPO}/${ADB_IMAGE_PATH:-database/adb-free}:${ADB_IMAGE_TAG:-latest-26ai}"
    exit 1
  fi
  $DOCKER_COMPOSE -f "$COMPOSE_FILE" --env-file "$ENV_FILE" up -d
else
  ADB_IMAGE="${ADB_IMAGE_REPO}/${ADB_IMAGE_PATH:-database/adb-free}:${ADB_IMAGE_TAG:-latest-26ai}"

  mkdir -p "$CERTS_DIR"
  # Resolve to an absolute path: some Podman clients (e.g. Podman Desktop's
  # WSL interop wrapper on Windows) fail to resolve a relative bind-mount
  # source against their working directory ("unsupported UNC path").
  CERTS_DIR_ABS="$(cd "$CERTS_DIR" && pwd)"
  $CONTAINER_CLI volume exists adb-data >/dev/null 2>&1 || $CONTAINER_CLI volume create adb-data >/dev/null
  $CONTAINER_CLI rm -f local-adb-free >/dev/null 2>&1 || true
  if ! $CONTAINER_CLI pull "$ADB_IMAGE"; then
    handle_pull_failure "$ADB_IMAGE"
    exit 1
  fi

  try_prefetch_pdb_via_windows

  # Rootless Podman in WSL usually has no working systemd user session (its
  # XDG_RUNTIME_DIR points at WSLg's socket dir instead), which crashes
  # Podman's systemd-backed healthcheck timer registration. Disable the
  # image's built-in HEALTHCHECK there to avoid that crash. The same
  # environment also picks the journald log driver even though journald
  # isn't actually reachable, which breaks `podman logs -f`. Force the
  # file-based log driver instead.
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
    --name local-adb-free \
    --hostname adbfree \
    --restart no \
    --cap-add SYS_ADMIN \
    --device /dev/fuse \
    -p 1521:1522 \
    -p 1522:1522 \
    -p 8443:8443 \
    -p 27017:27017 \
    -e "WORKLOAD_TYPE=${ADB_WORKLOAD_TYPE:-ATP}" \
    -e "WALLET_PASSWORD=${ADB_WALLET_PASSWORD}" \
    -e "ADMIN_PASSWORD=${ADB_ADMIN_PASSWORD}" \
    -v adb-data:/u01 \
    -v "$CERTS_DIR_ABS:/u01/ords/certs:ro" \
    "${HEALTHCHECK_FLAGS[@]}" \
    "${LOG_DRIVER_FLAGS[@]}" \
    "$ADB_IMAGE"
fi

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
    # NOTE: the pkill pattern below is deliberately written as "[o]rds.war"
    # rather than "ords.war". Since this whole command is itself passed as a
    # single argument to `bash -c`, a plain "ords.war" pattern would appear
    # verbatim in THIS process's own command line and pkill -f would match
    # (and kill) itself before ever reaching the real ORDS java process. The
    # classic "[x]pattern" bracket trick avoids that self-match while still
    # matching the real target.
    $CONTAINER_CLI exec local-adb-free bash -c '
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

echo ""
echo "=== ADB Free container started ==="
echo ""
echo "Waiting for the database and APEX/ORDS to become ready (this takes a few minutes on first run) ..."
echo "  (Live logs: $CONTAINER_CLI logs -f local-adb-free)"
echo ""

READY_URL="https://localhost:8443/ords/apex"
MAX_WAIT_SECONDS=1800
POLL_INTERVAL=15
elapsed=0
is_ready=false

if command -v curl &>/dev/null; then
  while [ "$elapsed" -lt "$MAX_WAIT_SECONDS" ]; do
    if [ -z "$($CONTAINER_CLI ps --filter name=local-adb-free --filter status=running -q 2>/dev/null)" ]; then
      echo ""
      echo "ERROR: local-adb-free stopped unexpectedly. Check logs with: $CONTAINER_CLI logs local-adb-free"
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
  echo "=== Ready! APEX and ORDS are responding (after ~${elapsed}s) ==="
else
  echo "=== Container is running, but readiness could not be confirmed automatically ==="
  echo "It may still be initializing. Check progress with: $CONTAINER_CLI logs -f local-adb-free"
fi
echo ""
echo "Access:"
echo "  APEX:             https://localhost:8443/ords/apex"
echo "  Database Actions: https://localhost:8443/ords/sql-developer"
echo "  DB (TLS):         localhost:1521"
echo "  DB (mTLS):        localhost:1522"
echo "  MongoDB API:      localhost:27017"
echo ""
echo "Credentials:"
echo "  Admin user:       ADMIN / (password in $ENV_FILE)"
echo ""
echo "Connect a DB client (SQLcl, SQL Developer, DBeaver, etc.):"
echo "  1. Get the wallet:  $CONTAINER_CLI cp local-adb-free:/u01/ords/wallet.zip ./wallet.zip"
echo "  2. Unzip it into a local folder (e.g. ./wallet) and point your client's TNS_ADMIN at it."
echo "  3. Connect as user ADMIN (password in $ENV_FILE) using a service name from that"
echo "     wallet's tnsnames.ora (e.g. <db_name>_high / _medium / _low / _tp / _tpurgent)."
echo ""

if [ "$DB_VERSION" = "19c" ]; then
  echo "NOTE: 19c image is AMD64 only. On Apple Silicon, this runs via emulation"
  echo "      which may be slower. Consider using Colima for better performance."
  echo ""
fi

