#!/usr/bin/env bash
# desc: Install local git hooks (pre-commit LF/CRLF validation)

set -euo pipefail

cd "$(dirname "${BASH_SOURCE[0]}")/.."

if ! command -v git >/dev/null 2>&1; then
  echo "Error: git is required but was not found on PATH."
  exit 1
fi

if [ ! -d .git ]; then
  echo "Error: this command must run from inside the repository."
  exit 1
fi

if [ ! -f .githooks/pre-commit ]; then
  echo "Error: .githooks/pre-commit is missing."
  exit 1
fi

chmod +x .githooks/pre-commit

git config core.hooksPath .githooks

echo "Installed local git hooks."
echo "Configured: core.hooksPath=.githooks"
echo "Hook active: .githooks/pre-commit"
