#!/usr/bin/env bash
set -Eeuo pipefail

ROOT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
ISO_DIR="${ROOT}/Pc/Os/Windows-10/Media"
ISO_PATH="${WORKSTATION_WINDOWS_ISO:-${ISO_DIR}/Windows.iso}"
DOWNLOAD_PAGE="https://www.microsoft.com/en-us/software-download/windows10ISO"
EXPECTED_SHA256="A6F470CA6D331EB353B815C043E327A347F594F37FF525F17764738FE812852E"

fail() { echo "WorkStation Windows-10 ISO: $*" >&2; exit 1; }

mkdir -p "${ISO_DIR}"

if [[ -f "${ISO_PATH}" ]]; then
  echo "WorkStation Windows-10 ISO: using existing ${ISO_PATH}"
else
  command -v curl >/dev/null || fail "curl is required"
  command -v sha256sum >/dev/null || fail "sha256sum is required"
  command -v awk >/dev/null || fail "awk is required"

  echo "WorkStation Windows-10 ISO: obtaining the current Microsoft download link..."
  url=""

  # Microsoft sometimes returns HTTP 403 to automated requests against the
  # public ISO page. Try Microsoft's ISO metadata endpoint first, then fall
  # back to the public page for environments where that endpoint is available.
  api_page="$(mktemp)"
  page="$(mktemp)"
  trap 'rm -f "${api_page}" "${page}"' EXIT

  if curl -fsSL --retry 3 --retry-delay 2 \
      -A 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 Chrome/131 Safari/537.36' \
      'https://api.msrc.microsoft.com/iso/download?os=Windows%2010&sku=Professional&arch=x64&lang=en-US' \
      -o "${api_page}"; then
    url="$(grep -Eo '"downloadUrl"[[:space:]]*:[[:space:]]*"[^"]+"' "\${api_page}" | head -n1 | sed -E 's/^"downloadUrl"[[:space:]]*:[[:space:]]*"//; s/"$//' | sed 's#\\/#/#g' || true)"
  fi

  if [[ -z "${url}" ]]; then
    if curl -fsSL --retry 3 --retry-delay 2 \
        -A 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 Chrome/131 Safari/537.36' \
        "${DOWNLOAD_PAGE}" -o "${page}"; then
      url="\$(grep -Eo 'https://software\.download\.prss\.microsoft\.com/dbazure/Win10_22H2_English_x64v1\.iso[^"<> ]*' "${page}" | head -n1 || true)"
    fi
  fi

  [[ -n "${url}" ]] || fail "Microsoft did not provide a current Windows 10 x64 ISO download link. The runner may be blocked from Microsoft's ISO service; set WORKSTATION_WINDOWS_ISO to an existing licensed ISO if needed"

  tmp="${ISO_PATH}.partial"
  rm -f "${tmp}"
  echo "WorkStation Windows-10 ISO: downloading the official Microsoft Windows 10 22H2 English x64 ISO..."
  curl -fL --retry 3 --retry-delay 2 -o "${tmp}" "${url}"

  echo "WorkStation Windows-10 ISO: verifying SHA-256..."
  actual="$(sha256sum "${tmp}" | awk '{print toupper($1)}')"
  if [[ "${actual}" != "${EXPECTED_SHA256}" ]]; then
    rm -f "${tmp}"
    fail "ISO SHA-256 mismatch (got ${actual}, expected ${EXPECTED_SHA256})"
  fi

  mv -f "${tmp}" "${ISO_PATH}"
  echo "WorkStation Windows-10 ISO: verified and saved to ${ISO_PATH}"
fi
