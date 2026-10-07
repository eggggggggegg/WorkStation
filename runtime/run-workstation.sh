#!/usr/bin/env bash
set -Eeuo pipefail

ROOT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
RUNTIME_ROOT="${WORKSTATION_RUNTIME_ROOT:-${RUNNER_TEMP:-${ROOT}/.runtime}/workstation}"
SESSION_ROOT="${RUNTIME_ROOT}/sessions/${WORKSTATION_NAME}"
HOME_ROOT="${SESSION_ROOT}/home"
LOG_ROOT="${SESSION_ROOT}/logs"
SAFE_NAME="$(printf '%s' "${WORKSTATION_NAME}" | tr '[:upper:]' '[:lower:]' | sed 's/[^a-z0-9_.-]/-/g')"
CONTAINER_NAME="workstation-${SAFE_NAME}"
PORT="${WORKSTATION_PORT:-8080}"

die() { echo "WorkStation: $*" >&2; exit 1; }
[[ "${WORKSTATION_NAME:-}" =~ ^[A-Za-z0-9][A-Za-z0-9._-]{0,62}$ ]] || die "invalid workstation name"
[[ -n "${WORKSTATION_PASSWORD:-}" && "${WORKSTATION_PASSWORD}" != *$'\\n'* && "${WORKSTATION_PASSWORD}" != *$'\\r'* ]] || die "password is required"
command -v docker >/dev/null || die "Docker is required"
command -v git >/dev/null || die "Git is required"
command -v rsync >/dev/null || die "rsync is required"

case "${WORKSTATION_OS:-}" in
  Ubuntu-26.04) IMAGE="ghcr.io/selkies-project/selkies/desktop:latest-ubuntu26.04" ;;
  Debian-Trixie) IMAGE="ghcr.io/selkies-project/selkies/desktop:latest-debiantrixie" ;;
  *) die "unsupported OS: ${WORKSTATION_OS:-}" ;;
esac

mkdir -p "${HOME_ROOT}" "${LOG_ROOT}"

GPU_ARGS=()
if command -v nvidia-smi >/dev/null 2>&1 && docker info --format '{{json .Runtimes}}' 2>/dev/null | grep -q '"nvidia"'; then
  GPU_ARGS+=(--gpus all)
elif [[ -d /dev/dri ]]; then
  GPU_ARGS+=(--device /dev/dri)
  if [[ -e /dev/dri/renderD128 ]]; then
    GPU_ARGS+=(--group-add "$(stat -c '%g' /dev/dri/renderD128)")
  fi
fi

cleanup() {
  set +e
  docker stop -t 20 "${CONTAINER_NAME}" >/dev/null 2>&1 || true
  if [[ -n "${TUNNEL_PID:-}" ]]; then
    kill "${TUNNEL_PID}" >/dev/null 2>&1 || true
    wait "${TUNNEL_PID}" >/dev/null 2>&1 || true
  fi
  sudo chown -R "$(id -u):$(id -g)" "${HOME_ROOT}" >/dev/null 2>&1 || true
  "${ROOT}/runtime/persistence.sh" save "${WORKSTATION_OS}" "${HOME_ROOT}" || echo "WorkStation: persistence save failed" >&2
}
trap cleanup EXIT INT TERM

echo "WorkStation: restoring ${WORKSTATION_OS}..."
"${ROOT}/runtime/persistence.sh" load "${WORKSTATION_OS}" "${HOME_ROOT}"


mkdir -p "${HOME_ROOT}/.config/workstation"
cat > "${HOME_ROOT}/.config/workstation/profile.yaml" <<EOF
name: "${WORKSTATION_NAME}"
profile: default
EOF
sudo chown -R 1000:1000 "${HOME_ROOT}"

docker rm -f "${CONTAINER_NAME}" >/dev/null 2>&1 || true
echo "WorkStation: starting ${IMAGE}..."

docker run -d \
  --name "${CONTAINER_NAME}" \
  --shm-size=2g \
  -p "127.0.0.1:${PORT}:8080" \
  -v "${HOME_ROOT}:/home/ubuntu" \
  -v "${ROOT}/runtime:/opt/workstation:ro" \
  -e "PASSWD=${WORKSTATION_PASSWORD}" \
  -e "SELKIES_BASIC_AUTH_USER=ubuntu" \
  -e "SELKIES_BASIC_AUTH_PASSWORD=${WORKSTATION_PASSWORD}" \
  -e "SELKIES_MODE=websockets" \
  -e "SELKIES_ENABLE_HTTPS=false" \
  "${GPU_ARGS[@]}" \
  "${IMAGE}" >/dev/null

# Configure GUI app launchers from inside the desktop container, where the
# installed applications and X11 environment actually exist.
docker exec "${CONTAINER_NAME}" /bin/bash /opt/workstation/configure-desktop-apps.sh /home/ubuntu || echo "WorkStation: desktop app configuration warning" >&2

echo "WorkStation: local address: http://127.0.0.1:${PORT}"

if command -v cloudflared >/dev/null 2>&1; then
  echo "WorkStation: starting temporary Cloudflare Quick Tunnel..."
  cloudflared tunnel --url "http://127.0.0.1:${PORT}" 2>&1 | tee "${LOG_ROOT}/cloudflared.log" &
  TUNNEL_PID=$!
  for _ in {1..30}; do
    URL="$(grep -Eo 'https://[-a-z0-9]+\\.trycloudflare\\.com' "${LOG_ROOT}/cloudflared.log" | head -n1 || true)"
    [[ -n "${URL}" ]] && echo "WorkStation: public URL: ${URL}" && break
    sleep 1
  done
else
  echo "WorkStation: cloudflared not installed; use the local address or install cloudflared on the runner."
fi

echo "WorkStation: running. Keep this workflow active while using the desktop."
echo "WorkStation: password is intentionally not printed."
docker wait "${CONTAINER_NAME}" >/dev/null
