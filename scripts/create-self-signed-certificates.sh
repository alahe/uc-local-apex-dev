#!/usr/bin/env bash
# desc: Create self-signed SSL certificates so ORDS serves HTTPS

set -e

# Function to check if command exists
command_exists() {
  command -v "$1" >/dev/null 2>&1
}

is_wsl() {
  [ -n "${WSL_DISTRO_NAME:-}" ] || grep -qi microsoft /proc/version 2>/dev/null
}

mkdir -p ./ssl/ ./ords-config/ssl/

echo "Generating certificates..."

CA_FILE=""
if command_exists openssl; then
  openssl req -x509 -out ./ssl/cert.crt -keyout ./ssl/key.key -days 9999 \
    -newkey rsa:2048 -nodes -sha256 \
    -subj '/CN=localhost' -extensions EXT -config <(
      printf "[dn]\nCN=localhost\n[req]\ndistinguished_name = dn\n[EXT]\nsubjectAltName=DNS:localhost,IP:127.0.0.1\nkeyUsage=digitalSignature\nextendedKeyUsage=serverAuth"
    )
elif command_exists mkcert; then
  echo "openssl not found - using mkcert instead."
  mkcert -install >/dev/null 2>&1 || true
  mkcert -cert-file ./ssl/cert.crt -key-file ./ssl/key.key localhost 127.0.0.1 ::1
  CA_FILE="$(mkcert -CAROOT)/rootCA.pem"
else
  echo "ERROR: neither openssl nor mkcert is available. Install one of them and re-run." >&2
  exit 1
fi

echo "Successfully generated certificates"
echo "  - Certificate: ./ssl/cert.crt"
echo "  - Private key: ./ssl/key.key"

chmod 644 ./ssl/key.key
chmod 644 ./ssl/cert.crt

cp -f ./ssl/cert.crt ./ords-config/ssl/
cp -f ./ssl/key.key ./ords-config/ssl/

echo "Successfully copied certificates to ORDS config directory. Restart ORDS to apply changes."

# ---------------------------------------------------------------------------
# Trust the certificate so browsers don't show a warning
# ---------------------------------------------------------------------------
if is_wsl; then
  echo "Detected WSL - trusting the certificate on the Windows host (not the WSL distro itself)."
  TRUST_FILE="${CA_FILE:-./ssl/cert.crt}"
  if command_exists powershell.exe && command_exists wslpath; then
    WIN_PATH=$(wslpath -w "$(readlink -f "$TRUST_FILE")" 2>/dev/null || true)
    if [ -n "$WIN_PATH" ] && powershell.exe -NoProfile -Command \
      "Import-Certificate -FilePath '$WIN_PATH' -CertStoreLocation Cert:\\CurrentUser\\Root" >/dev/null 2>&1; then
      echo "Trusted the certificate in the Windows current-user certificate store (no admin rights needed)."
    else
      echo "Could not import the certificate automatically. To trust it manually, run in Windows PowerShell:"
      echo "  Import-Certificate -FilePath '$WIN_PATH' -CertStoreLocation Cert:\\CurrentUser\\Root"
    fi
  else
    echo "No Windows interop (powershell.exe) available from this WSL distro."
    echo "To trust it manually, copy $TRUST_FILE to Windows and in PowerShell run:"
    echo "  Import-Certificate -FilePath '<path-to-file>' -CertStoreLocation Cert:\\CurrentUser\\Root"
  fi
  exit 0
fi

# Detect OS and install certificate (non-WSL Linux/macOS)
OS=$(uname -s)
case "$OS" in
Linux*)
  if [ "$EUID" -ne 0 ]; then
    echo "Skipping system trust-store install (not running as root)."
    echo "Re-run with sudo to also trust ./ssl/cert.crt system-wide, or import it manually."
    exit 0
  fi

  echo "Detected Linux OS"
  echo "  - Installing certificate to system trust store"

  # Check for different Linux distributions
  if [ -f /etc/debian_version ]; then
    cp "./ssl/cert.crt" /usr/local/share/ca-certificates/
    update-ca-certificates
  elif [ -f /etc/redhat-release ]; then
    cp "./ssl/cert.crt" /etc/pki/ca-trust/source/anchors/
    update-ca-trust extract
  else
    echo "Unsupported Linux distribution. Please install the certificate manually."
    exit 1
  fi
  ;;
Darwin*)
  KEYCHAIN="/Library/Keychains/System.keychain"

  echo "Installing certificate for macOS..."
  # Add to system keychain
  security add-trusted-cert -d -r trustRoot -k "$KEYCHAIN" "./ssl/cert.crt"

  # Set all trust settings to always trust
  security set-key-partition-list -D "Mozilla" -S "Mozilla" -k "$KEYCHAIN" "./ssl/cert.crt" 2>/dev/null

  # Verify installation
  if security find-certificate -c "$DOMAIN" "$KEYCHAIN" >/dev/null 2>&1; then
    echo "Certificate successfully installed and trusted in macOS Keychain"
    echo "Note: For Firefox, you'll need to manually import the certificate:"
    echo "1. Open Firefox"
    echo "2. Go to Preferences/Settings"
    echo "3. Search for 'certificates'"
    echo "4. Click 'View Certificates'"
    echo "5. Go to 'Authorities' tab"
    echo "6. Click 'Import' and select: ./ssl/cert.crt"
    echo "7. Check 'Trust this CA to identify websites'"
  else
    echo "Warning: Certificate installation verification failed"
  fi
  ;;
*)
  echo "Unsupported operating system: $OS"
  echo "Please install the certificate manually."
  exit 1
  ;;
esac

echo "Successfully installed certificate to system trust store"
echo "Please restart ORDS to apply changes: $DOCKER_COMPOSE restart ords-26ai"
echo "Access ORDS via HTTPS: https://localhost:8443/ords/_/landing"
