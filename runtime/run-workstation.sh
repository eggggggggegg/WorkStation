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
  Windows-10)
    exec "${ROOT}/runtime/run-windows-vm.sh"
    ;;
  *) die "unsupported OS: ${WORKSTATION_OS:-}" ;;
esac

mkdir -p "${HOME_ROOT}" "${LOG_ROOT}"

if ! docker info >/dev/null 2>&1; then die "Docker daemon is unavailable"; fi
if [[ "${PORT}" =~ ^[0-9]+$ ]] && (( PORT < 1024 || PORT > 65535 )); then die "invalid workstation port: ${PORT}"; fi
if command -v ss >/dev/null 2>&1 && ss -ltn "( sport = :${PORT} )" 2>/dev/null | grep -q LISTEN; then die "port ${PORT} is already in use"; fi

GPU_ARGS=()
if command -v nvidia-smi >/dev/null 2>&1 && docker info --format '{{json .Runtimes}}' 2>/dev/null | grep -q '"nvidia"'; then
  GPU_ARGS+=(--gpus all)
elif [[ -d /dev/dri ]]; then
  GPU_ARGS+=(--device /dev/dri)
  if [[ -e /dev/dri/renderD128 ]]; then
    GPU_ARGS+=(--group-add "$(stat -c '%g' /dev/dri/renderD128)")
  fi
fi

AUTOSAVE_PID=""

save_now() {
  set +e
  sudo chown -R "$(id -u):$(id -g)" "${HOME_ROOT}" >/dev/null 2>&1 || true
  "${ROOT}/runtime/persistence.sh" save "${WORKSTATION_OS}" "${HOME_ROOT}" || echo "WorkStation: persistence save failed" >&2
}

start_autosave() {
  (
    trap 'exit 0' INT TERM EXIT
    while true; do
      sleep "${WORKSTATION_AUTOSAVE_SECONDS:-60}" || exit 0
      echo "WorkStation: autosaving workspace..."
      save_now
    done
  ) &
  AUTOSAVE_PID=$!
}

cleanup() {
  set +e
  # Persist before teardown because canceled GitHub steps have a short grace period.
  if [[ -n "${AUTOSAVE_PID:-}" ]]; then
    kill "${AUTOSAVE_PID}" >/dev/null 2>&1 || true
    wait "${AUTOSAVE_PID}" >/dev/null 2>&1 || true
  fi
  save_now
  docker stop -t 20 "${CONTAINER_NAME}" >/dev/null 2>&1 || true
  if [[ -n "${TUNNEL_PID:-}" ]]; then
    kill "${TUNNEL_PID}" >/dev/null 2>&1 || true
    wait "${TUNNEL_PID}" >/dev/null 2>&1 || true
  fi
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

docker pull "${IMAGE}" >>"${LOG_ROOT}/docker-pull.log" 2>&1 || { tail -n 80 "${LOG_ROOT}/docker-pull.log" >&2 || true; die "Docker image pull failed"; }

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
  "${IMAGE}" >"${LOG_ROOT}/docker-run.log" 2>&1 || { tail -n 80 "${LOG_ROOT}/docker-run.log" >&2 || true; docker logs --tail 80 "${CONTAINER_NAME}" >&2 2>/dev/null || true; die "desktop container failed to start"; }

ready=0
for _ in {1..60}; do
  if ! docker inspect --format "{{.State.Running}}" "${CONTAINER_NAME}" 2>/dev/null | grep -q true; then
    break
  fi
  # Selkies uses a WebSocket browser endpoint, so "/" is not a reliable
  # HTTP-200 readiness probe. Verify that its published TCP port is open.
  if timeout 2 bash -c "</dev/tcp/127.0.0.1/${PORT}" 2>/dev/null; then
    ready=1
    break
  fi
  sleep 2
done
if (( ready != 1 )); then
  echo "WorkStation: desktop container did not open port ${PORT}." >&2
  docker port "${CONTAINER_NAME}" >&2 2>/dev/null || true
  docker inspect --format 'state={{.State.Status}} exit={{.State.ExitCode}} error={{.State.Error}}' "${CONTAINER_NAME}" >&2 2>/dev/null || true
  docker exec "${CONTAINER_NAME}" bash -lc 'ss -ltnp 2>/dev/null || netstat -ltnp 2>/dev/null || true' >&2 2>/dev/null || true
  docker logs --tail 160 "${CONTAINER_NAME}" >&2 2>/dev/null || true
  die "desktop service failed readiness check"
fi

# Restore cached system apps first, then configure GUI launchers from inside
# the desktop container where the installed applications and X11 environment exist.
for _ in {1..10}; do docker exec "${CONTAINER_NAME}" /bin/bash /opt/workstation/provision-apps.sh && break; sleep 2; done || echo "WorkStation: app restore warning" >&2
for _ in {1..10}; do docker exec "${CONTAINER_NAME}" /bin/bash /opt/workstation/configure-desktop-apps.sh /home/ubuntu && break; sleep 2; done || echo "WorkStation: desktop app configuration warning" >&2

echo "WorkStation: local address: http://127.0.0.1:${PORT}"

if command -v curl >/dev/null 2>&1; then
  :
else
  die "curl is required for desktop readiness checks"
fi

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
  die "cloudflared is required because the GitHub-hosted runner is not directly reachable from the browser"
fi

echo "WorkStation: running. Keep this workflow active while using the desktop."
echo "WorkStation: password is intentionally not printed."
echo "WorkStation: automatic persistence is enabled (${WORKSTATION_AUTOSAVE_SECONDS:-60}s interval)."

# Periodic saves protect work even when GitHub cancels the long-running step.
start_autosave
docker wait "${CONTAINER_NAME}" >/dev/null
