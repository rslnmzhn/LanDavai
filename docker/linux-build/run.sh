#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
IMAGE_NAME="${LANDA_LINUX_BUILD_IMAGE:-landa-linux-build:local}"
DOCKERFILE_PATH="${ROOT_DIR}/docker/linux-build/Dockerfile"
DEFAULT_COMMAND=(bash docker/linux-build/in_container_release_checks.sh)

if [[ ! -f "${DOCKERFILE_PATH}" ]]; then
  echo "Dockerfile not found: ${DOCKERFILE_PATH}" >&2
  exit 1
fi

docker build -t "${IMAGE_NAME}" -f "${DOCKERFILE_PATH}" "${ROOT_DIR}/docker/linux-build"

if [[ $# -gt 0 ]]; then
  COMMAND=("$@")
else
  COMMAND=("${DEFAULT_COMMAND[@]}")
fi

DOCKER_TTY_ARGS=()
if [[ -t 0 && -t 1 ]]; then
  DOCKER_TTY_ARGS=(-it)
fi

docker run --rm "${DOCKER_TTY_ARGS[@]}" \
  -e APPIMAGE_BUILDER_VERSION="${APPIMAGE_BUILDER_VERSION:-1.0.3}" \
  -v "${ROOT_DIR}:/workspace" \
  -w /workspace \
  "${IMAGE_NAME}" \
  "${COMMAND[@]}"
