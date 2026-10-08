#!/usr/bin/env bash
set -euo pipefail

export DISPLAY=${DISPLAY:-:99}
export XDG_RUNTIME_DIR=${XDG_RUNTIME_DIR:-/tmp/xdg-runtime}
mkdir -p "$XDG_RUNTIME_DIR"
chmod 700 "$XDG_RUNTIME_DIR"

# Reinstall manually selected APT applications from the previous session.
# The base Mint image is recreated on every Actions run.
if [ -s /persistent-system/apt-manual-packages.txt ]; then
  sudo apt-get update
  xargs -r sudo apt-get install -y --no-install-recommends < /persistent-system/apt-manual-packages.txt || true
  sudo rm -rf /var/lib/apt/lists/*
fi

# Restore Flatpak applications when the previous session installed any.
if command -v flatpak >/dev/null 2>&1 && [ -s /persistent-system/flatpak-apps.txt ]; then
  while IFS= read -r app; do
    [ -n "$app" ] || continue
    flatpak install -y flathub "$app" || true
  done < /persistent-system/flatpak-apps.txt
fi

Xvfb "$DISPLAY" -screen 0 1920x1080x24 -ac +extension GLX +render -noreset >/tmp/Xvfb.log 2>&1 &
XVFB_PID=$!

cleanup() {
  kill "$XVFB_PID" 2>/dev/null || true
}
trap cleanup EXIT INT TERM

until xdpyinfo -display "$DISPLAY" >/dev/null 2>&1; do
  sleep 0.2
done

xset -display "$DISPLAY" s off || true
xset -display "$DISPLAY" -dpms || true

dwm >/tmp/dwm.log 2>&1 &

exec /opt/selkies/bin/selkies \
  --public \
  --port=8080 \
  --enable-https=false \
  --basic-auth-user="${SELKIES_BASIC_AUTH_USER:-workstation}" \
  --basic-auth-password="${SELKIES_BASIC_AUTH_PASSWORD:?SELKIES_BASIC_AUTH_PASSWORD is required}" \
  --enable-resize=true \
  --encoder=h264enc
