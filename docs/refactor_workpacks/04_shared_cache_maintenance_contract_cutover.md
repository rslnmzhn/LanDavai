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

## PR1 Inventory Result

PR1 for this workpack is inventory-only.
No bridge deletion or callback cutover happens here.
The purpose of this note is to freeze the exact maintenance seam so PR2 can cut it over without guessing.

### Baseline Check

- `SharedCacheCatalog` remains the canonical owner of shared-cache metadata truth.
- `SharedCacheIndexStore` remains the canonical owner of shared-cache index truth.
- `FilesFeatureStateOwner` remains the canonical owner of files explorer/navigation/view state.
- The current problem is not metadata/index truth ownership drift.
- The current problem is the remaining maintenance relay path split across:
  - `SharedCacheCatalogBridge`
  - `DiscoveryPage`
  - `DiscoveryController`
  - `FileExplorerPage.launch(...)` callback/listenable parameters

### Production read/progress paths found

- `lib/features/discovery/application/shared_cache_catalog_bridge.dart`
  - `summarizeOwnerSharedContent(...)`
    - operation type: read, bridge relay
    - initiator: `DiscoveryPage._handleSharedRecacheFromFiles(...)`
    - downstream target: `SharedCacheCatalog.loadOwnerCaches(...)` then `SharedCacheCatalog.ownerCaches` and `SharedCacheIndexStore.readIndexEntries(...)`
    - classification: production path, compatibility residue
  - `listShareableVideoFiles(...)`
    - operation type: read, bridge relay
    - initiator: `DiscoveryPage._reloadShareableVideoFiles(...)`
    - downstream target: `SharedCacheCatalog.loadOwnerCaches(...)`, `SharedCacheCatalog.ownerCaches`, `SharedCacheIndexStore.readIndexEntries(...)`
    - classification: production path, compatibility residue
  - `listShareableLocalDirectory(...)`
    - operation type: read, bridge relay
    - classification: no current production caller found in `lib/`; test/support only
- `lib/features/discovery/presentation/discovery_page.dart`
  - `_handleSharedRecacheFromFiles(...)`
    - operation type: read preflight + command relay
    - initiator: files refresh action via callback bundle
    - downstream target: `SharedCacheCatalogBridge.summarizeOwnerSharedContent(...)` then `DiscoveryController.recacheSharedContent(...)`
    - classification: production path, compatibility residue
  - `_reloadShareableVideoFiles(...)`
    - operation type: read, bridge relay
    - initiator: discovery page init/update and local video-link UI refresh
    - downstream target: `SharedCacheCatalogBridge.listShareableVideoFiles(...)`
    - classification: production path, compatibility residue
  - `_openFileExplorer()`
    - operation type: callback relay and progress relay setup
    - initiator: discovery side menu files entry
    - downstream target: `FileExplorerPage.launch(...)`
    - classification: production path, compatibility residue
  - `_ActionBar` / bottom action bar
    - operation type: progress observation
    - initiator: discovery page render path
    - downstream target: `DiscoveryController.isSharedRecacheInProgress`, `sharedRecacheProgress`, `sharedRecacheDetails`
    - classification: production path, maintenance progress currently lives in controller shell
- `lib/features/files/presentation/file_explorer_page.dart`
  - `FileExplorerPage.launch(...)`
    - operation type: files entry surface
    - receives foreign maintenance callbacks/listenables/getters:
      - `onRecacheSharedFolders`
      - `onRemoveSharedCache`
      - `recacheStateListenable`
      - `isSharedRecacheInProgress`
      - `sharedRecacheProgress`
      - `sharedRecacheDetails`
    - classification: production path, compatibility residue
  - `_FileExplorerPageState.build(...)`
    - operation type: progress observation / callback capability gating
    - initiator: file explorer render path
    - downstream target: callback bundle and foreign listenable from discovery shell
    - classification: production path, compatibility residue
  - `_handleRefreshAction(...)`
    - operation type: command dispatch
    - initiator: file explorer refresh/recache action
    - downstream target: `widget.onRecacheSharedFolders!(owner.normalizedVirtualCurrentFolder)`
    - classification: production path, compatibility residue
  - `_removeSharedCacheFromEntry(...)`
    - operation type: command dispatch
    - initiator: file explorer delete/remove shared cache action
    - downstream target: `widget.onRemoveSharedCache(cacheId, entry.name)`
    - classification: production path, compatibility residue
- `lib/features/files/presentation/file_explorer_page.dart`
  - `_buildLaunchRoots(...)`, `_loadOwnerCaches(...)`, `_listShareableLocalDirectory(...)`
    - operation type: direct owner-backed read path
    - initiator: file explorer virtual-root loading
    - downstream target: `SharedCacheCatalog.loadOwnerCaches(...)`, `SharedCacheCatalog.ownerCaches`, `SharedCacheIndexStore.readIndexEntries(...)`
    - classification: production path, canonical owner-backed behavior, not bridge residue

### Production write/command paths found

- `lib/features/files/presentation/file_explorer_page.dart`
  - `_handleRefreshAction(...)`
    - command dispatch from files
    - legacy route: files -> discovery callback -> discovery page -> controller -> shared-cache owners
- `lib/features/files/presentation/file_explorer_page.dart`
  - `_removeSharedCacheFromEntry(...)`
    - command dispatch from files
    - legacy route: files -> discovery callback -> discovery page -> controller -> `SharedCacheCatalog.deleteCache(...)`
- `lib/features/discovery/presentation/discovery_page.dart`
  - `_handleSharedRecacheFromFiles(...)`
    - callback relay
    - legacy route: files callback -> bridge summary read -> controller recache command
- `lib/features/discovery/presentation/discovery_page.dart`
  - `_handleRemoveSharedCacheFromFiles(...)`
    - callback relay
    - legacy route: files callback -> controller remove command
- `lib/features/discovery/application/discovery_controller.dart`
  - `recacheSharedContent(...)`
    - command execution + progress truth + cooldown truth
    - downstream target: `SharedCacheCatalog.refreshOwnerSelectionCacheEntries(...)`, `upsertOwnerFolderCache(...)`, `refreshOwnerFolderSubdirectoryEntries(...)`
    - classification: production path, maintenance truth currently lives in controller shell
  - `removeSharedCacheById(...)` and `removeSharedCache(...)`
    - command execution
    - downstream target: `SharedCacheCatalog.deleteCache(...)`
    - classification: production path, maintenance command currently lives in controller shell

### Callback bundle inventory

- `onRecacheSharedFolders`
  - created in: `DiscoveryPage._openFileExplorer()`
  - passed to: `FileExplorerPage.launch(...)`
  - consumed in: `_FileExplorerPageState.build(...)` for capability gating and `_handleRefreshAction(...)` for write dispatch
  - behavior: maintenance write behavior with preflight read
  - duplication: duplicates a maintenance command surface that should be owner-backed instead of page callback-backed
- `onRemoveSharedCache`
  - created in: `DiscoveryPage._openFileExplorer()`
  - passed to: `FileExplorerPage.launch(...)`
  - consumed in: `_FileExplorerPageState.build(...)` for capability gating and `_removeSharedCacheFromEntry(...)` for write dispatch
  - behavior: maintenance write behavior
  - duplication: duplicates a maintenance command surface that should be owner-backed instead of page callback-backed
- `recacheStateListenable`
  - created in: `DiscoveryPage._openFileExplorer()` as `_controller`
  - passed to: `FileExplorerPage.launch(...)`
  - consumed in: `_FileExplorerPageState.build(...)` via `Listenable.merge(...)`
  - behavior: progress observation relay
  - duplication: duplicates a maintenance progress source that should be read directly from a dedicated maintenance boundary
- `isSharedRecacheInProgress`
  - created in: `DiscoveryPage._openFileExplorer()` as closure over controller getter
  - passed to: `FileExplorerPage.launch(...)`
  - consumed in: `_isSharedRecacheRunning`, `_buildRefreshActionIcon(...)`, shared status card rendering
  - behavior: progress/state read
  - duplication: duplicates controller-held maintenance state in a foreign screen contract
- `sharedRecacheProgress`
  - created in: `DiscoveryPage._openFileExplorer()` as closure over controller getter
  - passed to: `FileExplorerPage.launch(...)`
  - consumed in: `_sharedRecacheProgressValue`, status card rendering, progress indicator rendering
  - behavior: progress read
  - duplication: duplicates controller-held maintenance progress in a foreign screen contract
- `sharedRecacheDetails`
  - created in: `DiscoveryPage._openFileExplorer()` as closure mapping `DiscoveryController.SharedRecacheProgress` into `SharedRecacheProgressDetails`
  - passed to: `FileExplorerPage.launch(...)`
  - consumed in: `_sharedRecacheDetailsValue`, `_SharedRecacheStatusCard`
  - behavior: progress/detail read plus compatibility type adaptation
  - duplication: duplicates a foreign maintenance progress model and proves the current route is still a compatibility relay

### Bridge behavior inventory

- `SharedCacheCatalogBridge` currently exposes:
  - `summarizeOwnerSharedContent(...)`
  - `listShareableVideoFiles(...)`
  - `listShareableLocalDirectory(...)`
- Current behavior in practice:
  - read-side only
  - relay-only
  - not a canonical owner
  - no production write path found through the bridge
- Current production readers:
  - `DiscoveryPage._handleSharedRecacheFromFiles(...)`
  - `DiscoveryPage._reloadShareableVideoFiles(...)`
- Current production writers:
  - none
- Current test/support readers:
  - `test/shared_cache_catalog_bridge_test.dart`
  - `test/smoke_test.dart`
  - `test/test_support/test_discovery_controller.dart`
- Exact owner-backed replacement pressure:
  - recache preflight summary should move behind the future shared-cache maintenance boundary
  - files virtual directory read does not need the bridge today; it already reads `SharedCacheCatalog` + `SharedCacheIndexStore` directly
  - `listShareableVideoFiles(...)` has only one production reader in `DiscoveryPage` and should not force the future maintenance boundary to become a broad read-everything bridge

### Production vs test/support coupling

Production maintenance coupling:

- `DiscoveryPage._openFileExplorer(...)` callback bundle creation
- `FileExplorerPage.launch(...)` callback/listenable/getter intake
- `DiscoveryPage._handleSharedRecacheFromFiles(...)`
- `DiscoveryPage._handleRemoveSharedCacheFromFiles(...)`
- `DiscoveryController.recacheSharedContent(...)`
- `DiscoveryController.removeSharedCacheById(...)`
- `DiscoveryController` recache progress getters
- `SharedCacheCatalogBridge` production reads used by discovery page

Test/support coupling:

- `test/shared_cache_catalog_bridge_test.dart`
  - encodes the bridge API directly; will need replacement or deletion in PR2/PR3
- `test/smoke_test.dart`
  - injects `sharedCacheCatalogBridge` into `DiscoveryPage` / `DiscoveryPageEntry` and asserts bridge usage
- `test/test_support/test_discovery_controller.dart`
  - exposes `TrackingSharedCacheCatalogBridge` in the UI harness
- `test/discovery_controller_shared_cache_catalog_test.dart`
  - protects `SharedCacheCatalog` owner-backed delete path and remains relevant after bridge/callback cleanup

No production caller was found for `SharedCacheCatalogBridge.listShareableLocalDirectory(...)`; that surface is currently test/support-only residue.

### PR2 seam contract

- `Legacy owner / legacy route`
  - read-side relay: `SharedCacheCatalogBridge`
  - command/progress relay: `DiscoveryPage` callback bundle into `DiscoveryController`
  - concrete legacy route:
    - files refresh/delete UI -> `FileExplorerPage.launch(...)` callback bundle ->
      `DiscoveryPage` relay methods ->
      `DiscoveryController` maintenance methods/getters ->
      `SharedCacheCatalog` / `SharedCacheIndexStore`
- `Target owner / target boundary`
  - derived planning helper name: `SharedCacheMaintenanceBoundary`
  - scope:
    - recache command
    - remove shared cache command
    - maintenance progress/cooldown/read model
    - recache preflight summary needed by confirmation UI
  - constraints:
    - not `DiscoveryPage`
    - not `DiscoveryController`
    - not `SharedCacheCatalogBridge`
    - must preserve `SharedCacheCatalog` metadata ownership and `SharedCacheIndexStore` index ownership
  - non-goal:
    - do not turn this boundary into a broad shared-cache read bridge; non-maintenance reads such as local shareable video listing should bypass the bridge directly through existing owners when `SharedCacheCatalogBridge` is deleted
- `Read switch point`
  - first production progress/read path to switch:
    - `FileExplorerPage.launch(...)` must stop reading foreign maintenance state through:
      - `recacheStateListenable`
      - `isSharedRecacheInProgress`
      - `sharedRecacheProgress`
      - `sharedRecacheDetails`
    - `DiscoveryPage._handleSharedRecacheFromFiles(...)` must stop calling `SharedCacheCatalogBridge.summarizeOwnerSharedContent(...)`
- `Write switch point`
  - first production command path to switch:
    - `FileExplorerPage._handleRefreshAction(...)` must stop calling `onRecacheSharedFolders`
    - `FileExplorerPage._removeSharedCacheFromEntry(...)` must stop calling `onRemoveSharedCache`
    - the files maintenance entry should dispatch directly to the future maintenance boundary instead of routing through `DiscoveryPage`
- `Forbidden writers`
  - `DiscoveryPage`
  - `DiscoveryController`
  - `FileExplorerPage`
  - widget-local callback bundles
  - `SharedCacheCatalogBridge`
  - `SharedFolderCacheRepository` as a maintenance-policy owner
- `Forbidden dual-write / dual-route paths`
  - future maintenance boundary + old `onRecacheSharedFolders` callback path
  - future maintenance boundary + old `onRemoveSharedCache` callback path
  - future maintenance boundary progress + old controller progress relay (`recacheStateListenable`, getter closures)
  - direct owner-backed summary path + `SharedCacheCatalogBridge.summarizeOwnerSharedContent(...)` in parallel on the same production flow
- `Expected consumers of the future maintenance boundary`
  - `DiscoveryPage` as UI consumer for confirmation/progress presentation only
  - `FileExplorerPage.launch(...)` as files entry consumer for recache/remove/progress
  - `DiscoveryPageEntry` as composition/injection site
- `Files PR2 will need to change`
  - must change:
    - `lib/features/discovery/application/shared_cache_catalog_bridge.dart`
    - `lib/features/discovery/presentation/discovery_page.dart`
    - `lib/features/files/presentation/file_explorer_page.dart`
    - `lib/app/discovery_page_entry.dart`
  - likely change:
    - new maintenance boundary file under an explicit application layer
    - `test/shared_cache_catalog_bridge_test.dart`
    - `test/smoke_test.dart`
    - `test/test_support/test_discovery_controller.dart`
    - shared-cache/files discovery regression tests that still encode the old bridge/callback contract

### PR1 conclusion

- PR2 is unblocked.
- The target maintenance boundary is explicit enough for a non-speculative cutover.
- No blocker was found that forces `05`, `06`, or `07` to run first.
- The seam definition does not require a new permanent bridge/helper-shell; it points to a narrow maintenance boundary and direct owner-backed reads where the bridge is currently over-serving.
