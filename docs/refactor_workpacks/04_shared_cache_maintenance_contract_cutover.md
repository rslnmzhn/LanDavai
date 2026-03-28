# Workpack 04: Shared-Cache Maintenance Contract Cutover

## Purpose

Delete the remaining shared-cache maintenance backchannel between discovery and files by removing `SharedCacheCatalogBridge` and the files recache/remove/progress callback bundle.

## Why This Exists Now

Current evidence:

- `SharedCacheCatalogBridge` still survives on the production path
- `DiscoveryPage -> FileExplorerPage.launch(...)` still passes:
  - `onRecacheSharedFolders`
  - `onRemoveSharedCache`
  - `recacheStateListenable`
  - recache progress/detail getters
- `FileExplorerPage` still consumes that bundle as a real cross-feature contract

This is the largest remaining callback residue from the completed tactical backlog.

## In Scope

- `lib/features/discovery/application/shared_cache_catalog_bridge.dart`
- `lib/features/discovery/presentation/discovery_page.dart`
- `lib/features/files/presentation/file_explorer_page.dart`
- any narrow maintenance boundary or command surface created for shared-cache recache/remove/progress
- related tests and smoke flows

## Out of Scope

- shared-cache metadata/index ownership redo
- files explorer state ownership redo
- remote browse ownership redo

## Target State

- files and discovery use an explicit shared-cache maintenance contract
- `SharedCacheCatalogBridge` is deleted
- files entry no longer accepts foreign recache/remove/progress callbacks or controller listenables
- discovery page is no longer the switchboard for shared-cache maintenance

## Pull Request Cycle

1. Inventory every remaining maintenance read/write path that still routes through the bridge or callback bundle.
2. Introduce the owner-backed maintenance contract and switch both files and discovery to it.
3. Delete `SharedCacheCatalogBridge` and the files callback bundle.
4. Run shared-cache integration tests, files/discovery smoke tests, then `flutter analyze` and `flutter test`.

## Dependencies

- current shared-cache owners (`SharedCacheCatalog`, `SharedCacheIndexStore`) are baseline

## Required Test Gates

- `GATE-02`
- `GATE-03`
- `GATE-07`
- `GATE-08`

## Completion Proof

- `SharedCacheCatalogBridge` is gone
- `FileExplorerPage.launch(...)` no longer exposes shared-cache maintenance callbacks or foreign progress listenables
- files/discovery maintenance flows stay green
