# Build, Release, And Packaging

This file summarizes the active build and packaging path for release artifacts.

## Main CI workflow

- `.github/workflows/build.yml`

Key jobs:

- `resolve_release`
- `build_android`
- `build_linux`
- `build_windows`
- `publish_release`

## GitHub Releases update contract

Stable updates must consume GitHub Releases as the only source of truth.

Current stable-channel rules:

- Only non-draft, non-prerelease releases are part of the stable update channel.
- Stable tags use exact semver tag format: `vX.Y.Z`.
- Stable version metadata comes from:
  - release tag: `vX.Y.Z`
  - manifest `release.version`: `X.Y.Z`
- Release title and release notes are not part of the update contract.

Each stable release publishes a machine-readable manifest:

- `landa-vX.Y.Z-release-manifest.json`

Manifest guarantees:

- `schemaVersion = 1`
- `release.channel = stable`
- `release.tag = vX.Y.Z`
- `release.version = X.Y.Z`
- `release.draft = false`
- `release.prerelease = false`
- `assets[]` entries carry:
  - `platform`
  - `arch`
  - `format`
  - `primary`
  - `fileName`
  - `size`
  - `sha256`
  - `downloadUrl`

Asset selection rules for a later updater:

- Select a stable release first.
- Read `landa-vX.Y.Z-release-manifest.json`.
- Filter `assets[]` by runtime `platform` and `arch`.
- Prefer `primary = true`.
- Do not infer update assets from release notes or arbitrary asset-order heuristics.

Current stable release asset names:

- Android:
  - `landa-vX.Y.Z-android-armeabi-v7a.apk`
  - `landa-vX.Y.Z-android-arm64-v8a.apk`
  - `landa-vX.Y.Z-android-x86_64.apk`
- Linux:
  - `landa-vX.Y.Z-linux-x86_64.AppImage`
  - `landa-vX.Y.Z-linux-x64.zip`
- Windows:
  - `landa-vX.Y.Z-windows-x64.zip`

Platform defaults in the manifest:

- Android ABI APKs are all `primary = true` for their matching ABI.
- Linux AppImage is `primary = true`.
- Linux ZIP bundle is `primary = false`.
- Windows ZIP bundle is `primary = true`.

## Linux raw bundle

- Build command: `flutter build linux --release`
- Linux launcher/template:
  - `linux/CMakeLists.txt`
  - `linux/runner/landa_launcher.sh.in`

Current bundle shape:

- `landa` is a launcher script for raw Linux bundle startup/recovery.
- `landa-bin` is the real ELF binary.

## AppImage packaging

- Recipe:
  - `.github/appimage/AppImageBuilder.yml`
  - `.github/appimage/landa.desktop`
- Packaging script:
  - `.github/scripts/package_linux_appimage.sh`

Current AppImage entrypoint:

- AppImage points to `landa-bin`, not the raw-bundle launcher script.

Workspace hygiene:

- AppImage packaging outputs are cleaned/ignored so `AppDir/` and related generated outputs do not pollute `git status`.

## Linux build container

- `docker/linux-build/*`

The containerized release checks run Linux build plus AppImage packaging.

## Desktop startup/runtime infrastructure

- Single-instance guard:
  - `lib/core/utils/single_instance_guard.dart`
- Linux launcher/runtime recovery tests:
  - `test/linux_bundle_launcher_template_test.dart`
  - `test/single_instance_guard_test.dart`

## Analyzer/build artifact handling

- Generated build artifacts under `build/` are excluded from analyzer scope through `analysis_options.yaml`.

## Current verification path

- `flutter analyze`
- `flutter test`
- Linux release and packaging steps in CI / docker scripts
