#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"

command -v git >/dev/null || { echo "git is required" >&2; exit 1; }
command -v rsync >/dev/null || { echo "rsync is required" >&2; exit 1; }

mkdir -p /var/lib/workstation/{persistence,sessions,locks}

echo "WorkStation filesystem initialized."
echo "Repository: $ROOT"
echo "Runtime: /var/lib/workstation"
