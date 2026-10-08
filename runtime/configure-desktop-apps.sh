#!/usr/bin/env bash
set -Eeuo pipefail

HOME_ROOT="${1:?home path required}"
DESKTOP_DIR="${HOME_ROOT}/.local/share/applications"
BIN_DIR="${HOME_ROOT}/.local/bin"
LOG_DIR="${HOME_ROOT}/.local/share/workstation/logs"
mkdir -p "${DESKTOP_DIR}" "${BIN_DIR}" "${LOG_DIR}"

if [[ -x /usr/bin/code || -x /usr/bin/code-insiders ]]; then
  CODE_BIN="/usr/bin/code"
  [[ -x "${CODE_BIN}" ]] || CODE_BIN="/usr/bin/code-insiders"

  # VS Code can inherit a broken/stale GPU cache from a previous desktop session.
  rm -rf "${HOME_ROOT}/.config/Code/GPUCache"

  cat > "${BIN_DIR}/workstation-code" <<EOF
#!/usr/bin/env bash
set -u
LOG_DIR="${HOME}/.local/share/workstation/logs"
LOG_FILE="${LOG_DIR}/vscode.log"
ELECTRON_LOG="${LOG_DIR}/vscode-electron.log"
mkdir -p "${LOG_DIR}"
{
  echo
  echo "===== VS Code launch $(date -Is) ====="
  echo "user=$(id -un) uid=$(id -u) home=${HOME}"
  echo "DISPLAY=${DISPLAY-}"
  echo "WAYLAND_DISPLAY=${WAYLAND_DISPLAY-}"
  echo "XDG_SESSION_TYPE=${XDG_SESSION_TYPE-}"
  echo "CODE_BIN=${CODE_BIN}"
  echo "args: $*"
  echo "--- version ---"
  "${CODE_BIN}" --version 2>&1 || true
  echo "--- launch ---"
} >> "${LOG_FILE}"

export ELECTRON_OZONE_PLATFORM_HINT=x11
export LIBGL_ALWAYS_SOFTWARE=1
export ELECTRON_ENABLE_LOGGING=1
export ELECTRON_LOG_FILE="${ELECTRON_LOG}"

"${CODE_BIN}" --disable-gpu --ozone-platform=x11 --verbose "$@" >> "${LOG_FILE}" 2>&1
STATUS=$?
echo "VS Code exit status: ${STATUS}" >> "${LOG_FILE}"
exit "${STATUS}"
EOF
  chmod +x "${BIN_DIR}/workstation-code"

  cat > "${DESKTOP_DIR}/visual-studio-code.desktop" <<EOF
[Desktop Entry]
Name=Visual Studio Code
Comment=Code editor
Exec=${BIN_DIR}/workstation-code %U
Terminal=false
Type=Application
Categories=Development;IDE;
StartupNotify=true
EOF

  SETTINGS="${HOME_ROOT}/.config/Code/User/settings.json"
  mkdir -p "$(dirname "${SETTINGS}")"
  if [[ ! -f "${SETTINGS}" ]]; then
    printf "%s\n" "{" "  \"terminal.integrated.gpuAcceleration\": \"off\"," "  \"window.titleBarStyle\": \"native\"" "}" > "${SETTINGS}"
  fi

  chown -R "$(id -u):$(id -g)" "${DESKTOP_DIR}" "${BIN_DIR}" "${HOME_ROOT}/.config/Code" "${LOG_DIR}" 2>/dev/null || true
  echo "WorkStation: configured VS Code for X11/software rendering with persistent diagnostics."
fi

cat > "${BIN_DIR}/workstation-app-installer" <<EOF
#!/usr/bin/env bash
set -Eeuo pipefail
exec /opt/workstation/app-installer-menu.sh
EOF
chmod +x "${BIN_DIR}/workstation-app-installer"

cat > "${DESKTOP_DIR}/workstation-app-installer.desktop" <<EOF
[Desktop Entry]
Name=WorkStation App Installer
Comment=Install Linux applications and packages
Exec=${BIN_DIR}/workstation-app-installer
Terminal=true
Type=Application
Categories=System;PackageManager;Utility;
StartupNotify=true
EOF

if command -v gnome-software >/dev/null 2>&1; then
  cat > "${BIN_DIR}/workstation-software" <<EOF
#!/usr/bin/env bash
set -u
LOG_DIR="${HOME}/.local/share/workstation/logs"
LOG_FILE="${LOG_DIR}/gnome-software.log"
mkdir -p "${LOG_DIR}"
{
  echo
  echo "===== GNOME Software launch $(date -Is) ====="
  echo "user=$(id -un) uid=$(id -u) home=${HOME}"
  echo "DISPLAY=${DISPLAY-}"
  echo "WAYLAND_DISPLAY=${WAYLAND_DISPLAY-}"
  echo "XDG_SESSION_TYPE=${XDG_SESSION_TYPE-}"
  echo "--- version ---"
  gnome-software --version 2>&1 || true
  echo "--- launch ---"
} >> "${LOG_FILE}"

export GDK_BACKEND=x11
export GSK_RENDERER=cairo
gnome-software --verbose >> "${LOG_FILE}" 2>&1
STATUS=$?
echo "GNOME Software exit status: ${STATUS}" >> "${LOG_FILE}"
exit "${STATUS}"
EOF
  chmod +x "${BIN_DIR}/workstation-software"

  cat > "${DESKTOP_DIR}/workstation-software.desktop" <<EOF
[Desktop Entry]
Name=Software
Comment=Install and manage applications
Exec=${BIN_DIR}/workstation-software
Terminal=true
Type=Application
Categories=System;PackageManager;
StartupNotify=true
EOF
fi

cat > "${BIN_DIR}/workstation-app-logs" <<EOF
#!/usr/bin/env bash
set -u
LOG_DIR="${HOME}/.local/share/workstation/logs"
echo "WorkStation application diagnostics"
echo "Log directory: ${LOG_DIR}"
echo
for log in vscode.log vscode-electron.log gnome-software.log; do
  echo "===== ${log} ====="
  if [[ -f "${LOG_DIR}/${log}" ]]; then
    tail -n 80 "${LOG_DIR}/${log}"
  else
    echo "(no log yet)"
  fi
  echo
done
read -r -p "Press Enter to close..." _
EOF
chmod +x "${BIN_DIR}/workstation-app-logs"

cat > "${DESKTOP_DIR}/workstation-app-logs.desktop" <<EOF
[Desktop Entry]
Name=WorkStation App Logs
Comment=View application launch diagnostics
Exec=${BIN_DIR}/workstation-app-logs
Terminal=true
Type=Application
Categories=System;Utility;
StartupNotify=true
EOF
