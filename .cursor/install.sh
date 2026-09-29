#!/usr/bin/env bash
# Idempotent Cloud Agent install: Python venv + pipeline dependencies.
# Runs from any cwd. On Linux it also installs python3-venv (PEP 668).
set -euo pipefail

root="$(cd "$(dirname "$0")/.." && pwd)"
cd "$root"

if command -v apt-get >/dev/null 2>&1; then
  if [ "$(id -u)" -eq 0 ]; then
    apt-get update
    apt-get install -y python3 python3-venv python3-pip
  else
    sudo apt-get update
    sudo apt-get install -y python3 python3-venv python3-pip
  fi
fi

python3 -m venv .venv
.venv/bin/pip install --upgrade pip
.venv/bin/pip install -r scripts/requirements.txt
