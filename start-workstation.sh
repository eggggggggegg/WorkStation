#!/usr/bin/env bash
set -euo pipefail

export DISPLAY=${DISPLAY:-:99}
export XDG_RUNTIME_DIR=${XDG_RUNTIME_DIR:-/tmp/xdg-runtime}
mkdir -p "$XDG_RUNTIME_DIR"
chmod 700 "$XDG_RUNTIME_DIR"

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

# The requested lightweight window manager.
dwm >/tmp/dwm.log 2>&1 &

# Selkies 2 serves the complete browser client from one port.
# WebSockets is the default transport, so no TURN server is needed here.
exec /opt/selkies/bin/selkies \
  --public \
  --port=8080 \
  --enable-https=false \
  --basic-auth-user="${SELKIES_BASIC_AUTH_USER:-workstation}" \
  --basic-auth-password="${SELKIES_BASIC_AUTH_PASSWORD:?SELKIES_BASIC_AUTH_PASSWORD is required}" \
  --enable-resize=true \
  --encoder=h264enc
