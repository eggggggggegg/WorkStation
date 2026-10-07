#!/usr/bin/env bash
set -Eeuo pipefail

INSTALLER="/opt/workstation/app-installer.sh"
clear
echo "================================"
echo "     WorkStation App Installer"
echo "================================"
echo
echo "1) Install an APT package"
echo "2) Install a .deb file"
echo "3) Install an AppImage"
echo "4) Install VS Code"
echo "5) Diagnose installed apps"
echo "6) Exit"
echo
read -r -p "Choose an option: " choice

case "${choice}" in
  1)
    read -r -p "APT package name(s): " packages
    # shellcheck disable=SC2086
    exec /bin/bash "${INSTALLER}" apt ${packages}
    ;;
  2)
    read -r -p "Path to .deb: " file
    exec "${INSTALLER}" deb "${file}"
    ;;
  3)
    read -r -p "Path to AppImage: " file
    exec "${INSTALLER}" appimage "${file}"
    ;;
  4)
    exec "${INSTALLER}" vscode
    ;;
  5)
    exec "${INSTALLER}" diagnose
    ;;
  6)
    exit 0
    ;;
  *)
    echo "Invalid option."
    exit 2
    ;;
esac
