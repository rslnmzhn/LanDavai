# Regression And Test Gates

This file is the active current-state summary of the main regression gates used in the repository.

## Always-on baseline

- `flutter analyze`
- `flutter test`

These remain the broad regression gates for the repo.

## Architecture guard

- `test/architecture_guard_test.dart`

Purpose:

- forbid `part / part of` under `lib/`
- prevent reintroduction of deleted bridges and callback backchannels
- protect key ownership seams

## UI and entry-flow coverage

- `test/smoke_test.dart`
- `test/blocked_entry_flow_regression_test.dart`
- `test/files_entry_flow_regression_test.dart`
- `test/history_entry_flow_regression_test.dart`
- `test/remote_share_viewer_flow_regression_test.dart`

Purpose:

- main discovery shell survivability
- Files entry flow
- History entry flow
- shared-cache maintenance actions
- remote shared-access browser behavior

## Transfer/shared-access coverage

- `test/transfer_session_coordinator_test.dart`
- `test/lan_discovery_service_protocol_handlers_test.dart`
- `test/remote_share_browser_test.dart`
- `test/remote_share_media_projection_boundary_test.dart`

Purpose:

- shared download handshake and direct-start path
- manifest/cache reuse
- folder-prefix download scaling
- receiver/preview continuity
- remote-share projection integrity

## Nearby-transfer coverage

- `test/nearby_transfer_entry_sheet_test.dart`
- `test/nearby_transfer_qr_view_test.dart`
- `test/nearby_transfer_scanner_view_test.dart`
- `test/nearby_transfer_receive_view_test.dart`
- `test/nearby_transfer_send_view_test.dart`

## Settings and desktop-runtime coverage

- `test/app_settings_sheet_test.dart`
- `test/single_instance_guard_test.dart`
- `test/duplicate_instance_notice_app_test.dart`

## When to update docs

Update this file when:

- a new regression gate becomes a required baseline proof
- an old gate is replaced or removed
- a new active feature seam gains dedicated regression coverage
