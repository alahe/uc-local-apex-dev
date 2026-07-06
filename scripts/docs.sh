#!/usr/bin/env bash
#
# Start the documentation site locally and open it in the browser.
#
# Usage:
#   ./local-26ai.sh docs            # localhost only
#   ./local-26ai.sh docs --share    # expose to network (for VMs, other machines)
#
# Prerequisites: npm (Node.js) must be installed.
# Dependencies are installed automatically on first run.

set -euo pipefail

DOCS_DIR="./docs"
SHARE=false

# Parse arguments
for arg in "$@"; do
  case "$arg" in
    --share|-s) SHARE=true ;;
  esac
done

if [ ! -d "$DOCS_DIR" ]; then
  echo "Error: docs/ directory not found."
  exit 1
fi

# Install dependencies if needed
if [ ! -d "$DOCS_DIR/node_modules" ]; then
  echo "Installing documentation dependencies..."
  (cd "$DOCS_DIR" && npm install)
fi

echo "Starting documentation server..."
echo "Press Ctrl+C to stop."
echo ""

# Build the dev command
DEV_CMD="npm run dev"
if [ "$SHARE" = true ]; then
  DEV_CMD="npm run dev -- --host"
  echo "Sharing on network — accessible from other machines."
  echo ""
fi

# Start the dev server in the background, wait for it, then open the browser
(cd "$DOCS_DIR" && $DEV_CMD) &
DEV_PID=$!

# Wait for the server to be ready
for i in $(seq 1 30); do
  if curl -s http://localhost:4321/products/uc-local-apex-dev/docs/ > /dev/null 2>&1; then
    if [ "$SHARE" = true ]; then
      # Show the network URL
      LOCAL_IP=$(ipconfig getifaddr en0 2>/dev/null || hostname -I 2>/dev/null | awk '{print $1}' || echo "your-ip")
      echo ""
      echo "Network URL: http://${LOCAL_IP}:4321/products/uc-local-apex-dev/docs/"
      echo ""
    fi

    # Open in browser
    if command -v open &>/dev/null; then
      open "http://localhost:4321/products/uc-local-apex-dev/docs/"
    elif command -v xdg-open &>/dev/null; then
      xdg-open "http://localhost:4321/products/uc-local-apex-dev/docs/"
    else
      echo "Open http://localhost:4321/products/uc-local-apex-dev/docs/ in your browser."
    fi
    break
  fi
  sleep 1
done

# Wait for the dev server process (Ctrl+C will kill it)
wait $DEV_PID
