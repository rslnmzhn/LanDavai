#!/usr/bin/env bash
set -euo pipefail

ASSETS_DIR=""
RELEASE_VERSION=""
RELEASE_TAG=""
REPOSITORY=""

usage() {
  cat <<'EOF'
Usage: generate_release_manifest.sh --assets-dir PATH --version X.Y.Z --tag vX.Y.Z --repository owner/repo

Generate the stable GitHub Releases update manifest for one release.
The manifest is written to:
  <assets-dir>/landa-vX.Y.Z-release-manifest.json

The script expects the release assets for the current version to already exist in
the assets directory with their final published names.
EOF
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --assets-dir)
      ASSETS_DIR="$2"
      shift 2
      ;;
    --version)
      RELEASE_VERSION="$2"
      shift 2
      ;;
    --tag)
      RELEASE_TAG="$2"
      shift 2
      ;;
    --repository)
      REPOSITORY="$2"
      shift 2
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    *)
      echo "Unknown argument: $1" >&2
      usage >&2
      exit 1
      ;;
  esac
done

if [[ -z "${ASSETS_DIR}" || -z "${RELEASE_VERSION}" || -z "${RELEASE_TAG}" || -z "${REPOSITORY}" ]]; then
  usage >&2
  exit 1
fi

if [[ ! -d "${ASSETS_DIR}" ]]; then
  echo "Assets directory not found: ${ASSETS_DIR}" >&2
  exit 1
fi

MANIFEST_PATH="${ASSETS_DIR}/landa-v${RELEASE_VERSION}-release-manifest.json"

python - "${ASSETS_DIR}" "${RELEASE_VERSION}" "${RELEASE_TAG}" "${REPOSITORY}" "${MANIFEST_PATH}" <<'PY'
import hashlib
import json
import pathlib
import sys

assets_dir = pathlib.Path(sys.argv[1])
version = sys.argv[2]
tag = sys.argv[3]
repository = sys.argv[4]
manifest_path = pathlib.Path(sys.argv[5])

asset_specs = [
    {
        "platform": "android",
        "arch": "armeabi-v7a",
        "format": "apk",
        "primary": True,
        "fileName": f"landa-v{version}-android-armeabi-v7a.apk",
    },
    {
        "platform": "android",
        "arch": "arm64-v8a",
        "format": "apk",
        "primary": True,
        "fileName": f"landa-v{version}-android-arm64-v8a.apk",
    },
    {
        "platform": "android",
        "arch": "x86_64",
        "format": "apk",
        "primary": True,
        "fileName": f"landa-v{version}-android-x86_64.apk",
    },
    {
        "platform": "linux",
        "arch": "x86_64",
        "format": "appimage",
        "primary": True,
        "fileName": f"landa-v{version}-linux-x86_64.AppImage",
    },
    {
        "platform": "linux",
        "arch": "x86_64",
        "format": "zip",
        "primary": False,
        "fileName": f"landa-v{version}-linux-x64.zip",
    },
    {
        "platform": "windows",
        "arch": "x86_64",
        "format": "zip",
        "primary": True,
        "fileName": f"landa-v{version}-windows-x64.zip",
    },
]

assets = []
for spec in asset_specs:
    asset_path = assets_dir / spec["fileName"]
    if not asset_path.is_file():
        raise SystemExit(f"Missing release asset for manifest generation: {asset_path}")
    sha256 = hashlib.sha256(asset_path.read_bytes()).hexdigest()
    asset = {
        **spec,
        "size": asset_path.stat().st_size,
        "sha256": sha256,
        "downloadUrl": f"https://github.com/{repository}/releases/download/{tag}/{spec['fileName']}",
    }
    assets.append(asset)

manifest = {
    "schemaVersion": 1,
    "release": {
        "channel": "stable",
        "tag": tag,
        "version": version,
        "draft": False,
        "prerelease": False,
    },
    "assets": assets,
}

manifest_path.write_text(json.dumps(manifest, indent=2) + "\n", encoding="utf-8")
print(manifest_path)
PY
