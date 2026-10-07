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
    echo "WorkStation: snap is not available; App Center will be skipped."
    return 0
  fi
  if ! snap list snap-store >/dev/null 2>&1; then
    sudo snap install snap-store || echo "WorkStation: App Center install failed; custom installer remains available." >&2
  fi
}

if [[ -f "${CACHE_ROOT}/vscode.deb" && ! -x /usr/bin/code ]]; then
  echo "WorkStation: restoring cached VS Code installation..."
  if command -v sudo >/dev/null 2>&1; then
    sudo apt-get update
    sudo env DEBIAN_FRONTEND=noninteractive apt-get install -y "${CACHE_ROOT}/vscode.deb"
  else
    echo "WorkStation: sudo is unavailable; skipping VS Code restore." >&2
  fi
fi

if [[ -x /usr/bin/code ]]; then
  repair_vscode_sandbox
fi

if [[ "${WORKSTATION_INSTALL_APPCENTER:-1}" == "1" ]]; then
  restore_appcenter
fi
