#!/usr/bin/env bash
set -Eeuo pipefail

CACHE_ROOT="/home/ubuntu/.cache/workstation/apps"
 
repair_vscode_sandbox() {
  local sandbox="/usr/share/code/chrome-sandbox"
  if [[ -e "${sandbox}" ]]; then
    if command -v sudo >/dev/null 2>&1; then
      sudo chown root:root "${sandbox}"
      sudo chmod 4755 "${sandbox}"
      echo "WorkStation: VS Code Chromium sandbox repaired."
    fi
  fi
}

restore_appcenter() {
  if ! command -v snap >/dev/null 2>&1; then
    echo "WorkStation: snap is not available; installing the GNOME Software app store fallback."
    if command -v sudo >/dev/null 2>&1; then
      sudo apt-get update
      sudo env DEBIAN_FRONTEND=noninteractive apt-get install -y gnome-software || true
    fi
    return 0
  fi
  if ! snap list snap-store >/dev/null 2>&1; then
    sudo snap install snap-store || {
      echo "WorkStation: App Center snap failed; installing GNOME Software fallback." >&2
      sudo apt-get update || true
      sudo env DEBIAN_FRONTEND=noninteractive apt-get install -y gnome-software || true
    }
  fi
}

if [[ -f "${CACHE_ROOT}/vscode.deb" && ! -x /usr/bin/code && ! -x /usr/bin/code-insiders ]]; then
  echo "WorkStation: restoring cached VS Code installation..."
  if command -v sudo >/dev/null 2>&1; then
    sudo apt-get update
    sudo env DEBIAN_FRONTEND=noninteractive apt-get install -y "${CACHE_ROOT}/vscode.deb"
  else
    echo "WorkStation: sudo is unavailable; skipping VS Code restore." >&2
  fi
fi

if [[ -x /usr/bin/code || -x /usr/bin/code-insiders ]]; then
  repair_vscode_sandbox
fi

if [[ ! -x /usr/bin/code && ! -x /usr/bin/code-insiders ]]; then
  echo "WorkStation: VS Code is not installed; installing the current stable build..."
  if /opt/workstation/app-installer.sh vscode; then
    echo "WorkStation: VS Code installed."
  else
    echo "WorkStation: VS Code installation failed; continuing without it." >&2
  fi
fi

if [[ -x /usr/bin/code || -x /usr/bin/code-insiders ]]; then
  repair_vscode_sandbox
fi

if [[ "${WORKSTATION_INSTALL_APPCENTER:-1}" == "1" ]]; then
  restore_appcenter
fi
