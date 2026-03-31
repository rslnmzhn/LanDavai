# Workpack 07: Shared-Folder-Cache Repository Split

## Purpose

Split the broad repository into narrow collaborators and reduce the repository
to thin row persistence only.

## Status

Completed.

## Target State (Baseline)

- `SharedCacheRecordStore` is the thin row-persistence port
- `SharedCacheThumbnailStore` is the thumbnail artifact port
- `SharedFolderCacheRepository` implements `SharedCacheRecordStore` only

## Dependencies

- `04_shared_cache_maintenance_contract_cutover.md`
- `06_remote_share_media_projection_cleanup.md`

## Required Test Gates

- `GATE-02`
- `GATE-04`
- `GATE-08`

## Completion Proof (Current Baseline)

- `SharedFolderCacheRepository` is a thin record store:
  - `lib/features/transfer/data/shared_folder_cache_repository.dart`
- `SharedCacheRecordStore` exists:
  - `lib/features/transfer/data/shared_cache_record_store.dart`
- `SharedCacheThumbnailStore` exists:
  - `lib/features/transfer/data/shared_cache_thumbnail_store.dart`
- guards forbid re-broadening:
  - `test/architecture_guard_test.dart`
