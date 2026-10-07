#!/usr/bin/env bash
set -Eeuo pipefail

ROOT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
APP_ROOT="${HOME}/Apps"
CACHE_ROOT="${HOME}/.cache/workstation/apps"
LOG_ROOT="${HOME}/.local/state/workstation"
mkdir -p "${APP_ROOT}" "${CACHE_ROOT}" "${LOG_ROOT}"

usage() {
  cat <<'EOF'
WorkStation App Installer

Usage:
  app-installer apt <package>...
  app-installer deb <file.deb>
  app-installer appimage <file.AppImage>
  app-installer vscode
  app-installer diagnose <command>

Supported:
  APT packages are installed with the system package manager.
  DEB files are validated and installed with apt so dependencies are resolved.
  AppImages are copied into ~/Apps/AppImages and a desktop launcher is created.
  VS Code is installed from Microsoft's official Debian package and configured
  for software rendering in virtualized/Selkies desktops.
EOF
}

need_cmd() { command -v "$1" >/dev/null 2>&1 || { echo "Missing required command: $1" >&2; exit 1; }; }

apt_install() {
  need_cmd sudo
  need_cmd apt-get
  sudo apt-get update
  sudo env DEBIAN_FRONTEND=noninteractive apt-get install -y "$@"
}

install_deb() {
  local file="${1:-}"
  [[ -f "${file}" ]] || { echo "DEB not found: ${file}" >&2; exit 2; }
  [[ "${file}" == *.deb ]] || { echo "Not a .deb file: ${file}" >&2; exit 2; }
  need_cmd dpkg-deb
  dpkg-deb --info "${file}" >/dev/null
  apt_install "${file}"
}

install_appimage() {
  local file="${1:-}"
  [[ -f "${file}" ]] || { echo "AppImage not found: ${file}" >&2; exit 2; }
  local name
  name="$(basename "${file}")"
  local target="${APP_ROOT}/AppImages/${name}"
  mkdir -p "${APP_ROOT}/AppImages"
  install -m 0755 "${file}" "${target}"
  local desktop_name
  desktop_name="${name%.AppImage}"
  desktop_name="$(printf '%s' "${desktop_name}" | tr -c 'A-Za-z0-9._-' '_')"
  mkdir -p "${HOME}/.local/share/applications"
  cat > "${HOME}/.local/share/applications/${desktop_name}.desktop" <<EOF
[Desktop Entry]
Name=${desktop_name}
Type=Application
Exec=${target} %U
Terminal=false
Categories=Utility;Development;
EOF
  echo "Installed AppImage: ${target}"
}

install_vscode() {
  need_cmd curl
  local deb="${CACHE_ROOT}/vscode.deb"
  echo "Downloading the current VS Code Debian package..."
  curl -fL --retry 3 --connect-timeout 15 \
    -o "${deb}.tmp" \
    "https://update.code.visualstudio.com/latest/linux-deb-x64/stable"
  mv "${deb}.tmp" "${deb}"
  install_deb "${deb}"
  configure_vscode
}

configure_vscode() {
  if command -v code >/dev/null 2>&1; then
    mkdir -p "${HOME}/.config/Code/User"
    local settings="${HOME}/.config/Code/User/settings.json"
    if [[ ! -f "${settings}" ]]; then
      printf '%s\n' '{' '  "terminal.integrated.gpuAcceleration": "off",' '  "window.titleBarStyle": "native"' '}' > "${settings}"
    else
      echo "VS Code settings already exist; leaving them unchanged."
    fi
  fi
}

diagnose() {
  echo "== WorkStation app diagnostics =="
  echo "OS: $(. /etc/os-release && printf '%s %s' "${ID}" "${VERSION_ID}")"
  echo "User: $(id)"
  echo "DISPLAY=${DISPLAY:-<unset>}"
  echo "WAYLAND_DISPLAY=${WAYLAND_DISPLAY:-<unset>}"
  echo "XDG_SESSION_TYPE=${XDG_SESSION_TYPE:-<unset>}"
  echo "HOME=${HOME}"
  echo "GPU devices:"
  ls -l /dev/dri 2>/dev/null || echo "  none"
  if command -v code >/dev/null 2>&1; then
    echo "VS Code: $(code --version 2>/dev/null | head -n1)"
    echo "VS Code executable: $(command -v code)"
  else
    echo "VS Code: not installed"
  fi
}

case "${1:-}" in
  apt)
    shift
    [[ $# -gt 0 ]] || { usage; exit 2; }
    apt_install "$@"
    ;;
  deb)
    shift
    install_deb "$1"
    ;;
  appimage)
    shift
    install_appimage "$1"
    ;;
  vscode)
    install_vscode
    ;;
  diagnose)
    diagnose
    ;;
  *)
    usage
    exit 2
    ;;
esac
