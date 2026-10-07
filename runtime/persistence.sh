#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
OS_ROOT="${ROOT}/Pc/Os"
RUNTIME_ROOT="${WORKSTATION_RUNTIME_ROOT:-${RUNNER_TEMP:-${ROOT}/.runtime}/workstation}"
LOCK_ROOT="${RUNTIME_ROOT}/locks"

usage() {
  echo "usage: ${0##*/} {load|save} <Osname> <path>" >&2
  exit 2
}

valid_os_name() {
  [[ "$1" =~ ^[A-Za-z0-9][A-Za-z0-9._-]*$ ]]
}

safe_os_root() {
  local os="$1"
  valid_os_name "$os" || { echo "invalid OS name" >&2; exit 2; }
  printf "%s\n" "${OS_ROOT}/${os}"
}

safe_files_root() {
  local os="$1"
  valid_os_name "${os}" || { echo "invalid OS name" >&2; exit 2; }
  printf '%s\n' "${OS_ROOT}/${os}/Files"
}

acquire_lock() {
  local os="$1"
  mkdir -p "${LOCK_ROOT}"
  local lock="${LOCK_ROOT}/${os}.lock"
  if ! mkdir "${lock}" 2>/dev/null; then
    echo "persistence is already locked for OS: ${os}" >&2
    exit 1
  fi
  LOCK_PATH="${lock}"
}

release_lock() {
  [[ -n "${LOCK_PATH:-}" ]] && rmdir -- "${LOCK_PATH}" 2>/dev/null || true
}
trap release_lock EXIT

load_os() {
  local os="$1" target="$2"
  local source
  source="$(safe_files_root "${os}")"
  acquire_lock "${os}"
  mkdir -p "${source}" "${target}"
  rsync -a --delete --no-owner --no-group --omit-dir-times "${source}/" "${target}/"
}

reject_persisted_secrets() {
  local root="$1"
  local bad
  bad="$(find "${root}" -type f \( \
    -name '.env' -o -name '.env.*' -o -name '*.pem' -o -name '*.key' \
    -o -name '*id_rsa*' -o -name '*id_ed25519*' -o -name 'credentials.json' \
  \) -print -quit)"
  if [[ -n "${bad}" ]]; then
    echo "refusing to persist probable secret: ${bad}" >&2
    return 1
  fi
}

save_os() {
  local os="$1" source="$2"
  local destination
  destination="$(safe_files_root "${os}")"

  [[ -d "${source}" ]] || { echo "source does not exist: ${source}" >&2; exit 1; }
  acquire_lock "${os}"
  mkdir -p "${destination}"
  reject_persisted_secrets "${source}"
  rsync -a --delete --exclude='.git/' "${source}/" "${destination}/"

  local relative="${destination#${ROOT}/}"
  git -C "${ROOT}" add -- "${relative}"

  if git -C "${ROOT}" diff --cached --quiet -- "${relative}"; then
    echo "no persistence changes for ${os}"
    return 0
  fi

  git -C "${ROOT}" -c user.name="WorkStation" -c user.email="workstation@users.noreply.github.com" commit -m "Persist files for ${os}"
  git -C "${ROOT}" push origin "${WORKSTATION_GIT_BRANCH:-main}"
}

case "${1:-}" in
  load|save)
    [[ $# -eq 3 ]] || usage
    "${1}_os" "$2" "$3"
    ;;
  *)
    usage
    ;;
esac
