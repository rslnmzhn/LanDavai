# Workpack 07: Shared-Folder-Cache Repository Split

## Purpose

Split `SharedFolderCacheRepository` into narrower data collaborators now that metadata and index ownership already live in explicit owners.

## Why This Exists Now

Current evidence:

- `SharedFolderCacheRepository` still mixes:
  - DB record IO
  - JSON index IO
  - folder indexing
  - pruning and rebinding helpers
  - thumbnail artifact IO
  - selection-cache helpers
- extracted owners still depend on one broad infra class with several reasons to change

## In Scope

- `lib/features/transfer/data/shared_folder_cache_repository.dart`
- `lib/features/transfer/application/shared_cache_catalog.dart`
- `lib/features/transfer/application/shared_cache_index_store.dart`
- `lib/features/files/application/preview_cache_owner.dart`
- `lib/features/discovery/application/remote_share_browser.dart`
- any narrower infra collaborators or ports introduced by the split

## Out of Scope

- shared-cache metadata/index ownership redo
- DB schema changes
- remote browse ownership redo

## Target State

- broad repository responsibilities are split into narrower collaborators
- owner boundaries depend on smaller infra ports instead of one god-repository
- any remaining repository wrapper is thin and no longer policy-heavy

## Pull Request Cycle

1. Inventory repository responsibilities and assign each one to a narrower infra role.
2. Extract collaborators or ports under the existing owners without changing shared-cache semantics.
3. Delete or drastically reduce the broad repository surface.
4. Run shared-cache consistency and remote-share media regressions, then `flutter analyze` and `flutter test`.

## Dependencies

- `04_shared_cache_maintenance_contract_cutover.md`
- `06_remote_share_media_projection_cleanup.md`

## Required Test Gates

- `GATE-02`
- `GATE-04`
- `GATE-08`

## Completion Proof

- `SharedFolderCacheRepository` no longer acts as a policy-heavy do-everything class
- owner boundaries read/write shared-cache data through narrower ports
- shared-cache and remote-share regressions stay green
