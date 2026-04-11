# Build, Release, And Packaging

This file summarizes the active build and packaging path for release artifacts.

## Main CI workflow

- `.github/workflows/build.yml`

Key jobs:

- `build_linux`
- `publish_release`

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
