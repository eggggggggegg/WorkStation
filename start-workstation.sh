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

# A complete X11 framebuffer with the extensions Selkies expects.
Xvfb "$DISPLAY" \
  -screen 0 1920x1080x24 \
  -s 0 -dpms \
  +extension COMPOSITE +extension DAMAGE +extension GLX +extension RANDR \
  +extension RENDER +extension MIT-SHM +extension XFIXES +extension XTEST \
  +iglx +render -nolisten tcp -ac -noreset -shmem >/tmp/Xvfb.log 2>&1 &
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

# Start a real Linux Mint Cinnamon session on the virtual display. Mint's
# Cinnamon desktop provides the panels, menu, file manager, settings, terminal,
# window manager, and normal desktop behavior instead of an empty X server.
pulseaudio --start --daemonize=true --exit-idle-time=-1 >/tmp/pulseaudio.log 2>&1 || true
export PULSE_SERVER=unix:${XDG_RUNTIME_DIR}/pulse/native

if command -v dbus-launch >/dev/null 2>&1 && command -v cinnamon-session >/dev/null 2>&1; then
  dbus-launch --exit-with-session cinnamon-session >/tmp/cinnamon.log 2>&1 &
  DESKTOP_PID=$!
else
  echo "Cinnamon session could not be started; falling back to a minimal window manager."
  dwm >/tmp/dwm.log 2>&1 &
  DESKTOP_PID=$!
fi

echo "========== WORKSTATION STREAM DIAGNOSTICS =========="
echo "DISPLAY=$DISPLAY"
echo "--- libva ---"
ldconfig -p 2>/dev/null | grep -E 'libva|libva-drm' || true
echo "--- pixelflux import ---"
/opt/selkies/bin/python -c 'import pixelflux; print("pixelflux OK:", pixelflux.__file__)' 2>&1 || true
echo "--- pcmflux import ---"
/opt/selkies/bin/python -c 'import pcmflux; print("pcmflux OK:", pcmflux.__file__)' 2>&1 || true
echo "--- Xvfb ---"
cat /tmp/Xvfb.log 2>/dev/null || true
echo "--- Cinnamon ---"
cat /tmp/cinnamon.log 2>/dev/null || true
echo "--- PulseAudio ---"
cat /tmp/pulseaudio.log 2>/dev/null || true
echo "--- X11 ---"
xdpyinfo -display "$DISPLAY" 2>&1 | head -n 40 || true
echo "===================================================="

# Keep Selkies logs in both the Actions/container log and a file that can be
# inspected after a failed session.
exec /opt/selkies/bin/selkies \
  --public \
  --port=8080 \
  --mode=websockets \
  --enable-https=false \
  --basic-auth-user="${SELKIES_BASIC_AUTH_USER:-workstation}" \
  --basic-auth-password="${SELKIES_BASIC_AUTH_PASSWORD:?SELKIES_BASIC_AUTH_PASSWORD is required}" \
  --enable-resize=true \
  --encoder=jpeg \
  --use-cpu=true \
  2> >(tee -a /tmp/selkies.log >&2)
