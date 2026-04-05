#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="${1:-$(pwd)}"
BUILD_DIR="${ROOT_DIR}/build/linux/x64/release"
MIMALLOC_URL="https://github.com/microsoft/mimalloc/archive/refs/tags/v2.1.2.tar.gz"
MIMALLOC_ARCHIVE="${BUILD_DIR}/mimalloc-2.1.2.tar.gz"
MIMALLOC_MD5="5179c8f5cf1237d2300e2d8559a7bc55"

ensure_md5_matches() {
  local file_path="$1"
  local expected_md5="$2"
  local actual_md5

  actual_md5="$(md5sum "${file_path}" | awk '{print $1}')"
  [[ "${actual_md5}" == "${expected_md5}" ]]
}

mkdir -p "${BUILD_DIR}"

# Remove stale extracted sources or prior corrupt archive so the plugin rebuilds
# against one known-good tarball instead of reusing partial residue.
rm -rf "${BUILD_DIR}/mimalloc" "${BUILD_DIR}/mimalloc-2.1.2"

if [[ -f "${MIMALLOC_ARCHIVE}" ]] && ensure_md5_matches "${MIMALLOC_ARCHIVE}" "${MIMALLOC_MD5}"; then
  echo "Using cached mimalloc archive: ${MIMALLOC_ARCHIVE}"
  exit 0
fi

rm -f "${MIMALLOC_ARCHIVE}" "${MIMALLOC_ARCHIVE}.tmp"

curl \
  --fail \
  --location \
  --retry 5 \
  --retry-all-errors \
  --retry-delay 2 \
  --output "${MIMALLOC_ARCHIVE}.tmp" \
  "${MIMALLOC_URL}"

if ! ensure_md5_matches "${MIMALLOC_ARCHIVE}.tmp" "${MIMALLOC_MD5}"; then
  rm -f "${MIMALLOC_ARCHIVE}.tmp"
  echo "Downloaded mimalloc archive failed checksum verification." >&2
  exit 1
fi

mv "${MIMALLOC_ARCHIVE}.tmp" "${MIMALLOC_ARCHIVE}"
echo "Prefetched mimalloc archive: ${MIMALLOC_ARCHIVE}"
