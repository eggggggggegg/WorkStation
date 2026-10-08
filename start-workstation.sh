#!/usr/bin/env bash
set -euo pipefail

export DISPLAY=:99

Xvfb "$DISPLAY" -screen 0 1920x1080x24 -ac +extension GLX +render -noreset >/tmp/Xvfb.log 2>&1 &
XVFB_PID=$!

cleanup() {
  kill "$XVFB_PID" 2>/dev/null || true
}
trap cleanup EXIT INT TERM

fluxbox >/tmp/fluxbox.log 2>&1 &

if command -v x11vnc >/dev/null 2>&1; then
  x11vnc -display "$DISPLAY" -forever -shared -nopw -rfbport 5900 >/tmp/x11vnc.log 2>&1 &
fi

if [ -n "${CLOUDFLARE_TUNNEL_TOKEN:-}" ]; then
  echo "A Cloudflare tunnel token was supplied."
  echo "Install cloudflared in the image and configure the tunnel endpoint here."
fi

echo "WorkStation desktop is running on DISPLAY=$DISPLAY"
while true; do
  sleep 30
done
