#!/usr/bin/env bash
set -Eeuo pipefail

ROOT="\$(cd -- "\$(dirname -- "\${BASH_SOURCE[0]}")/.." && pwd)"
ISO_DIR="\${ROOT}/Pc/Os/Windows-10/Media"
ISO_PATH="\${WORKSTATION_WINDOWS_ISO:-\${ISO_DIR}/Windows.iso}"
DOWNLOAD_PAGE="https://www.microsoft.com/en-us/software-download/windows10ISO"
EXPECTED_SHA256="A6F470CA6D331EB353B815C043E327A347F594F37FF525F17764738FE812852E"

fail() { echo "WorkStation Windows-10 ISO: \$*" >&2; exit 1; }

mkdir -p "\${ISO_DIR}"

if [[ -f "\${ISO_PATH}" ]]; then
  echo "WorkStation Windows-10 ISO: using existing \${ISO_PATH}"
else
  command -v curl >/dev/null || fail "curl is required"
  command -v sha256sum >/dev/null || fail "sha256sum is required"
  command -v awk >/dev/null || fail "awk is required"

  echo "WorkStation Windows-10 ISO: obtaining the current Microsoft download link..."
  page="\$(mktemp)"
  trap 'rm -f "\${page}"' EXIT
  curl -fsSL --retry 3 --retry-delay 2 -A 'Mozilla/5.0' "\${DOWNLOAD_PAGE}" -o "\${page}"

  url="\$(grep -Eo 'https://software\\.download\\.prss\\.microsoft\\.com/dbazure/Win10_22H2_English_x64v1\\.iso[^"<> ]*' "\${page}" | head -n1 || true)"
  [[ -n "\${url}" ]] || fail "Microsoft did not expose a current Windows 10 x64 ISO link; use WORKSTATION_WINDOWS_ISO to provide one"

  tmp="\${ISO_PATH}.partial"
  rm -f "\${tmp}"
  echo "WorkStation Windows-10 ISO: downloading the official Microsoft Windows 10 22H2 English x64 ISO..."
  curl -fL --retry 3 --retry-delay 2 -o "\${tmp}" "\${url}"

  echo "WorkStation Windows-10 ISO: verifying SHA-256..."
  actual="\$(sha256sum "\${tmp}" | awk '{print toupper(\$1)}')"
  if [[ "\${actual}" != "\${EXPECTED_SHA256}" ]]; then
    rm -f "\${tmp}"
    fail "ISO SHA-256 mismatch (got \${actual}, expected \${EXPECTED_SHA256})"
  fi

  mv -f "\${tmp}" "\${ISO_PATH}"
  echo "WorkStation Windows-10 ISO: verified and saved to \${ISO_PATH}"
fi
