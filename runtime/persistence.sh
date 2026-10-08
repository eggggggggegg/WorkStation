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
valid_os_name() { [[ "$1" =~ ^[A-Za-z0-9][A-Za-z0-9._-]*$ ]]; }
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
release_lock() { [[ -n "${LOCK_PATH:-}" ]] && rmdir -- "${LOCK_PATH}" 2>/dev/null || true; }
trap release_lock EXIT

RSYNC_EXCLUDES=(
  --exclude='.cache/' --exclude='.local/share/Trash/'
  --exclude='.config/Code/Cache/' --exclude='.config/Code/CachedData/' --exclude='.config/Code/logs/'
  --exclude='.npm/' --exclude='.cargo/registry/' --exclude='.cargo/git/' --exclude='.rustup/'
  --exclude='.config/workstation/runtime/' --exclude='.workstation-chunks/'
  --exclude='.ssh/' --exclude='.gnupg/' --exclude='.aws/' --exclude='.azure/'
  --exclude='.config/gh/' --exclude='.config/gcloud/' --exclude='.kube/'
  --exclude='.env' --exclude='.env.*' --exclude='credentials.json' --exclude='token.json'
  --exclude='**/cookies.sqlite' --exclude='**/key4.db' --exclude='**/logins.json'
  --exclude='**/Login Data' --exclude='**/Cookies'
  # Browser single-instance locks are runtime state. Persisting them can make a
  # newly created container think Chrome/Firefox is still running elsewhere.
  --exclude='**/SingletonLock' --exclude='**/SingletonSocket' --exclude='**/SingletonCookie'
  --exclude='**/parent.lock' --exclude='**/.parentlock' --exclude='**/lock'
)

clear_browser_locks() {
  local root="$1"
  # These files are safe to discard when no browser is running; the desktop is
  # not started during the initial restore, and the second restore runs before
  # the user can launch a browser.
  find "${root}" -type f \( \
    -name 'SingletonLock' -o -name 'SingletonSocket' -o -name 'SingletonCookie' -o \
    -name 'parent.lock' -o -name '.parentlock' -o -name 'lock' \
  \) -delete 2>/dev/null || true
}


load_os() {
  local os="$1" target="$2" source
  source="$(safe_files_root "${os}")"
  acquire_lock "${os}"
  mkdir -p "${source}" "${target}"
  # The desktop container can create root-owned files in the mounted home.
  # Run the restore as root so rsync can replace/delete those files reliably.
  sudo rsync -a --delete --no-owner --no-group --omit-dir-times "${RSYNC_EXCLUDES[@]}" "${source}/" "${target}/"
  command -v python3 >/dev/null 2>&1 || { echo "WorkStation: python3 is required for large-file restore" >&2; exit 1; }
  sudo python3 "${ROOT}/runtime/persist-workspace.py" load "${target}" "${source}"
  clear_browser_locks "${target}"
}

save_os() {
  local os="$1" source="$2" destination relative
  destination="$(safe_files_root "${os}")"
  [[ -d "${source}" ]] || { echo "source does not exist: ${source}" >&2; exit 1; }
  acquire_lock "${os}"
  # Never snapshot stale browser single-instance locks.
  clear_browser_locks "${source}"
  mkdir -p "${destination}"
  # The container may leave root-owned files behind; use root for the snapshot
  # so saves cannot fail merely because the desktop changed ownership.
  sudo rsync -a --delete "${RSYNC_EXCLUDES[@]}" "${source}/" "${destination}/"
  command -v python3 >/dev/null 2>&1 || { echo "WorkStation: python3 is required for large-file persistence" >&2; exit 1; }
  sudo python3 "${ROOT}/runtime/persist-workspace.py" save "${source}" "${destination}/.workstation-chunks"
  relative="${destination#${ROOT}/}"
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
  *) usage ;;
esac
