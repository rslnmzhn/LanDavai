# Workpack 06: Remote-Share Media Projection Cleanup

## Purpose

Remove controller-side remote-share thumbnail IO and move media projection
behind an explicit boundary.

## Status

Completed.

## Target State (Baseline)

- media projection owned by `RemoteShareMediaProjectionBoundary`
- controller does not read/write thumbnail bytes directly
- thumbnail artifact IO uses a narrow thumbnail store

## Dependencies

- `04_shared_cache_maintenance_contract_cutover.md`

## Required Test Gates

- `GATE-04`
- `GATE-08`

## Completion Proof (Current Baseline)

- `RemoteShareMediaProjectionBoundary` orchestrates thumbnail sync
  - `lib/features/discovery/application/remote_share_media_projection_boundary.dart`
- thumbnail IO uses `SharedCacheThumbnailStore`
- controller no longer imports thumbnail storage directly
  - enforced by `test/architecture_guard_test.dart`
- remote-share media tests remain green:
  - `test/remote_share_media_projection_boundary_test.dart`
