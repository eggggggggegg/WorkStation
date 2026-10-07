#!/usr/bin/env bash
set -Eeuo pipefail

# Reinstall cached system apps into a fresh Selkies container. The package
# cache lives under /home/ubuntu and therefore survives WorkStation sessions.
CACHE_ROOT="/home/ubuntu/.cache/workstation/apps"

if [[ -f "${CACHE_ROOT}/vscode.deb" && ! -x /usr/bin/code ]]; then
  echo "WorkStation: restoring cached VS Code installation..."
  if command -v sudo >/dev/null 2>&1; then
    sudo apt-get update
    sudo env DEBIAN_FRONTEND=noninteractive apt-get install -y "${CACHE_ROOT}/vscode.deb"
  else
    echo "WorkStation: sudo is unavailable; skipping VS Code restore." >&2
  fi
fi
