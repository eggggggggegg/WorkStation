#!/usr/bin/env bash
set -euo pipefail

# Repository-backed OS file persistence.
# Usage:
#   persistence.sh load <Osname> <target>
#   persistence.sh save <Osname> <source>
#
# The repository is expected to be the current working tree.
# GitHub credentials are provided by the environment, never by this script.

ROOT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
OS_ROOT="${ROOT}/Pc/Os"
RUNTIME_ROOT="${WORKSTATION_RUNTIME_ROOT:-/var/lib/workstation}"
LOCK_ROOT="${RUNTIME_ROOT}/locks"

usage() {
  echo "usage: $0 {load|save} <Osname> <path>" >&2
  exit 2
}

valid_os_name() {
  [[ "$1" =~ ^[A-Za-z0-9][A-Za-z0-9._-]*$ ]]
}

safe_files_root() {
  local os="$1"
  valid_os_name "$os" || { echo "invalid OS name" >&2; exit 2; }
  printf '%s\n' "${OS_ROOT}/${os}/Files"
}

acquire_lock() {
  mkdir -p "$LOCK_ROOT"
  local lock="${LOCK_ROOT}/${1}.lock"
  if ! mkdir "$lock" 2>/dev/null; then
    echo "persistence is already locked for OS: $1" >&2
    exit 1
  fi
  trap 'rmdir -- "$lock" 2>/dev/null || true' EXIT
}

load_os() {
  local os="$1"
  local target="$2"
  local source
  source="$(safe_files_root "$os")"

  acquire_lock "$os"
  mkdir -p "$source" "$target"

  # Pull the latest persisted state before restoring it.
  git -C "$ROOT" pull --ff-only origin "${WORKSTATION_GIT_BRANCH:-main}"

  # rsync keeps the target clean while preserving the tracked user tree.
  rsync -a --delete "${source}/" "${target}/"
}

save_os() {
  local os="$1"
  local source="$2"
  local destination
  destination="$(safe_files_root "$os")"

  acquire_lock "$os"
  mkdir -p "$destination"

  rsync -a --delete --exclude='.git/' "${source}/" "${destination}/"

  git -C "$ROOT" add -- "${destination#"$ROOT/"}"

  if git -C "$ROOT" diff --cached --quiet -- "${destination#"$ROOT/"}"; then
    echo "no persistence changes for $os"
    return 0
  fi

  git -C "$ROOT" commit -m "Persist files for $os"
  git -C "$ROOT" push origin "${WORKSTATION_GIT_BRANCH:-main}"
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
