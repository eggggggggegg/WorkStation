#!/usr/bin/env bash
set -Eeuo pipefail

HOME_ROOT="${1:?home path required}"
DESKTOP_DIR="${HOME_ROOT}/.local/share/applications"
BIN_DIR="${HOME_ROOT}/.local/bin"
mkdir -p "${DESKTOP_DIR}" "${BIN_DIR}"

if [[ -x /usr/bin/code || -x /usr/bin/code-insiders ]]; then
  CODE_BIN="/usr/bin/code"
  [[ -x "${CODE_BIN}" ]] || CODE_BIN="/usr/bin/code-insiders"

  cat > "${BIN_DIR}/workstation-code" <<EOF
#!/usr/bin/env bash
set -Eeuo pipefail
export ELECTRON_OZONE_PLATFORM_HINT=x11
export LIBGL_ALWAYS_SOFTWARE=1
exec "${CODE_BIN}" --disable-gpu "$@"
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
    printf '%s\n' '{' '  "terminal.integrated.gpuAcceleration": "off",' '  "window.titleBarStyle": "native"' '}' > "${SETTINGS}"
  fi

  chown -R "$(id -u):$(id -g)" "${DESKTOP_DIR}" "${BIN_DIR}" "${HOME_ROOT}/.config/Code" 2>/dev/null || true
  echo "WorkStation: configured VS Code for X11/software rendering."
fi

cat > "${BIN_DIR}/workstation-app-installer" <<'EOF'
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

# Reliable GTK software-center launcher for CI desktops.
if command -v gnome-software >/dev/null 2>&1; then
  cat > "${DESKTOP_DIR}/workstation-software.desktop" <<EOF
[Desktop Entry]
Name=Software
Comment=Install and manage applications
Exec=env GDK_BACKEND=x11 gnome-software
Terminal=false
Type=Application
Categories=System;PackageManager;
StartupNotify=true
EOF
fi
