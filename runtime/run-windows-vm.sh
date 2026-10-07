#!/usr/bin/env bash
set -Eeuo pipefail

ROOT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
RUNTIME_ROOT="${WORKSTATION_RUNTIME_ROOT:-${RUNNER_TEMP:-${ROOT}/.runtime}/workstation}"
SESSION_NAME="${WORKSTATION_NAME:-windows-10}"
SESSION_ROOT="${RUNTIME_ROOT}/sessions/${SESSION_NAME}"
VM_ROOT="${SESSION_ROOT}/windows-10"
LOG_ROOT="${SESSION_ROOT}/logs"
DISK="${WORKSTATION_WINDOWS_DISK:-${VM_ROOT}/windows-10.qcow2}"
ISO="${WORKSTATION_WINDOWS_ISO:-${ROOT}/Pc/Os/Windows-10/Media/Windows.iso}"
VNC_PORT="${WORKSTATION_WINDOWS_VNC_PORT:-5900}"
WEB_PORT="${WORKSTATION_PORT:-8080}"
RAM="${WORKSTATION_WINDOWS_RAM:-4G}"
CPUS="${WORKSTATION_WINDOWS_CPUS:-2}"
QEMU_LOG="${LOG_ROOT}/windows-qemu.log"
NOVNC_LOG="${LOG_ROOT}/windows-novnc.log"
QMP_SOCKET="${VM_ROOT}/qmp.sock"
QEMU_PID=""
NOVNC_PID=""

fail() { echo "WorkStation Windows-10: $*" >&2; exit 1; }

mkdir -p "${VM_ROOT}" "${LOG_ROOT}"
command -v qemu-system-x86_64 >/dev/null || fail "QEMU is not installed"
command -v qemu-img >/dev/null || fail "qemu-img is not installed"
command -v novnc_proxy >/dev/null || fail "noVNC is not installed"
[[ -f "${ISO}" ]] || fail "Windows 10 ISO not found at ${ISO}; provide a licensed ISO via WORKSTATION_WINDOWS_ISO"

ACCEL=""
if [[ -e /dev/kvm && -r /dev/kvm && -w /dev/kvm ]]; then
  ACCEL="kvm"
elif [[ "${WORKSTATION_WINDOWS_ALLOW_TCG:-0}" == "1" ]]; then
  ACCEL="tcg"
else
  cat >&2 <<MSG
WorkStation Windows-10: KVM is unavailable on this GitHub-hosted runner.
GitHub does not officially support nested virtualization on hosted runners.
Set WORKSTATION_WINDOWS_ALLOW_TCG=1 only if you intentionally want slow software emulation.
MSG
  exit 2
fi

if [[ ! -f "${DISK}" ]]; then
  echo "WorkStation Windows-10: creating fresh ${WORKSTATION_WINDOWS_DISK_SIZE:-64G} qcow2 disk..."
  qemu-img create -f qcow2 "${DISK}" "${WORKSTATION_WINDOWS_DISK_SIZE:-64G}" >>"${QEMU_LOG}" 2>&1
fi

cleanup() {
  set +e
  [[ -n "${NOVNC_PID}" ]] && kill "${NOVNC_PID}" >/dev/null 2>&1 || true
  [[ -n "${QEMU_PID}" ]] && kill "${QEMU_PID}" >/dev/null 2>&1 || true
  wait "${NOVNC_PID}" >/dev/null 2>&1 || true
  wait "${QEMU_PID}" >/dev/null 2>&1 || true
  rm -f "${QMP_SOCKET}"
}
trap cleanup EXIT INT TERM

VNC_DISPLAY=$((VNC_PORT - 5900))
QEMU_ARGS=(
  -name "WorkStation-Windows-10-${SESSION_NAME}"
  -machine q35
  -accel "${ACCEL}"
  -cpu max
  -smp "${CPUS}"
  -m "${RAM}"
  -drive "file=${DISK},if=virtio,format=qcow2"
  -drive "file=${ISO},media=cdrom,readonly=on"
  -boot order=d,menu=on
  -device virtio-vga
  -device virtio-net-pci,netdev=net0
  -netdev user,id=net0
  -device ich9-intel-hda
  -device hda-duplex
  -usb
  -device usb-tablet
  -vnc "127.0.0.1:${VNC_DISPLAY},password=on"
  -qmp "unix:${QMP_SOCKET},server=on,wait=off"
  -no-reboot
)

echo "WorkStation Windows-10: starting QEMU with ${ACCEL} acceleration..."
qemu-system-x86_64 "${QEMU_ARGS[@]}" >>"${QEMU_LOG}" 2>&1 &
QEMU_PID=$!

for _ in {1..30}; do
  kill -0 "${QEMU_PID}" 2>/dev/null || { tail -n 80 "${QEMU_LOG}" >&2 || true; fail "QEMU exited during startup"; }
  [[ -S "${QMP_SOCKET}" ]] && break
  sleep 1
done

[[ -S "${QMP_SOCKET}" ]] || fail "QEMU QMP socket did not appear"

# Set the VNC password through QMP so it never appears in the process command line.
# VNC authentication itself is limited to 8 characters by the VNC protocol.
export WORKSTATION_VNC_PASSWORD="${WORKSTATION_PASSWORD:0:8}"
python3 - "${QMP_SOCKET}" <<'PY'
import json
import os
import socket
import sys
import time

path = sys.argv[1]
password = os.environ.get("WORKSTATION_VNC_PASSWORD", "")
if not password:
    raise SystemExit("WORKSTATION_PASSWORD is required for Windows VNC authentication")

sock = socket.socket(socket.AF_UNIX, socket.SOCK_STREAM)
sock.settimeout(5)
sock.connect(path)
sock.recv(65536)
sock.sendall(b'{"execute":"qmp_capabilities"}\r\n')
sock.recv(65536)
command = {
    "execute": "set_password",
    "arguments": {"protocol": "vnc", "password": password},
}
sock.sendall((json.dumps(command) + "\r\n").encode())
response = sock.recv(65536)
if b'"error"' in response:
    raise SystemExit("QEMU rejected the VNC password")
sock.close()
PY

unset WORKSTATION_VNC_PASSWORD

novnc_proxy --listen "127.0.0.1:${WEB_PORT}" --vnc "127.0.0.1:${VNC_PORT}" --heartbeat 30 >>"${NOVNC_LOG}" 2>&1 &
NOVNC_PID=$!

sleep 2
kill -0 "${NOVNC_PID}" 2>/dev/null || { tail -n 80 "${NOVNC_LOG}" >&2 || true; fail "noVNC exited during startup"; }

echo "WorkStation Windows-10: browser desktop is available on http://127.0.0.1:${WEB_PORT}"
echo "WorkStation Windows-10: QEMU acceleration=${ACCEL}"
echo "WorkStation Windows-10: VNC authentication is enabled"
echo "WorkStation Windows-10: disk=${DISK}"
echo "WorkStation Windows-10: ISO=${ISO}"

if command -v cloudflared >/dev/null 2>&1 && [[ "${WORKSTATION_WINDOWS_PUBLIC:-1}" == "1" ]]; then
  echo "WorkStation Windows-10: starting temporary Cloudflare Quick Tunnel..."
  cloudflared tunnel --url "http://127.0.0.1:${WEB_PORT}" 2>&1 | tee "${LOG_ROOT}/cloudflared.log" &
  TUNNEL_PID=$!
  for _ in {1..30}; do
    URL="$(grep -Eo 'https://[-a-z0-9]+\.trycloudflare\.com' "${LOG_ROOT}/cloudflared.log" | head -n1 || true)"
    [[ -n "${URL}" ]] && echo "WorkStation Windows-10: public URL: ${URL}" && break
    sleep 1
  done
fi

echo "WorkStation Windows-10: running."
wait "${QEMU_PID}"
