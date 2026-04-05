#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="/workspace"
WORK_DIR="/tmp/landa-local-release-work"
OUTPUT_DIR="${ROOT_DIR}/build/docker_linux_release"

if [[ ! -f "${ROOT_DIR}/pubspec.yaml" ]]; then
  echo "Repository is not mounted at ${ROOT_DIR}." >&2
  exit 1
fi

rm -rf "${WORK_DIR}"
mkdir -p "${WORK_DIR}" "${OUTPUT_DIR}"

rsync -a --delete \
  --exclude build \
  --exclude .dart_tool \
  "${ROOT_DIR}/" "${WORK_DIR}/"

git config --global --add safe.directory "${WORK_DIR}"

cd "${WORK_DIR}"

flutter config --enable-linux-desktop
flutter pub get
flutter analyze
flutter test

RESOLVER_OUTPUT="$(bash .github/scripts/resolve_release_version.sh --dry-run)"
echo "${RESOLVER_OUTPUT}"

RELEASE_VERSION="$(echo "${RESOLVER_OUTPUT}" | sed -n 's/^release_version=//p' | head -n 1)"
RELEASE_VERSION_CODE="$(echo "${RESOLVER_OUTPUT}" | sed -n 's/^android_version_code=//p' | head -n 1)"

if [[ -z "${RELEASE_VERSION}" || -z "${RELEASE_VERSION_CODE}" ]]; then
  echo "Unable to parse release version output." >&2
  exit 1
fi

bash .github/scripts/apply_release_version.sh \
  --version "${RELEASE_VERSION}" \
  --version-code "${RELEASE_VERSION_CODE}"

flutter pub get
CXXFLAGS="-Wno-error=unused-but-set-variable" flutter build linux --release -v
APP_VERSION="${RELEASE_VERSION}" bash .github/scripts/package_linux_appimage.sh

cp "landa-v${RELEASE_VERSION}-linux-x86_64.AppImage" "${OUTPUT_DIR}/"
rm -rf "${OUTPUT_DIR}/linux-bundle"
cp -r build/linux/x64/release/bundle "${OUTPUT_DIR}/linux-bundle"

echo "Local Linux release artifacts are available in ${OUTPUT_DIR}:"
echo "  - ${OUTPUT_DIR}/landa-v${RELEASE_VERSION}-linux-x86_64.AppImage"
echo "  - ${OUTPUT_DIR}/linux-bundle"
