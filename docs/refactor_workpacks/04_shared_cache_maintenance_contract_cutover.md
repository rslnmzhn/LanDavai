# Workpack 04: Shared-Cache Maintenance Contract Cutover

## Purpose

Remove the shared-cache maintenance backchannel between discovery and files by
replacing it with an explicit owner-backed boundary.

## Status

Completed.

## Target State (Baseline)

- `SharedCacheMaintenanceBoundary` is the maintenance contract
- `SharedCacheCatalogBridge` is deleted and forbidden
- no discovery/files callback bundle remains

## Required Test Gates

- `GATE-02`
- `GATE-03`
- `GATE-07`
- `GATE-08`

## Completion Proof (Current Baseline)

- `SharedCacheMaintenanceBoundary` is used by discovery and files
- `SharedCacheCatalogBridge` absent under `lib/`
- architecture guards enforce the removal:
  - `test/architecture_guard_test.dart`
- files recache/remove entry UI is still reachable:
  - `test/blocked_entry_flow_regression_test.dart`
