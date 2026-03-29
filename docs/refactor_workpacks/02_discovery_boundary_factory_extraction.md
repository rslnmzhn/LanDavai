# Workpack 02: Discovery Boundary Factory Extraction

## Purpose

Убрать большой discovery composition root из widget lifecycle.
Это не новый ownership split.
Это extraction of assembly and lifecycle wiring out of `DiscoveryPageEntry`.

## Current evidence

- `lib/app/discovery_page_entry.dart` still:
  - calls `AppDatabase.instance`
  - constructs repositories, services, owners, and controller
  - keeps a private `_DiscoveryBoundary`
  - mixes widget lifecycle with composition lifecycle
- the file remains a large app-shell assembly surface instead of a thin entry widget

## Target state

- explicit discovery boundary factory or app-level composition object builds the graph
- `DiscoveryPageEntry` becomes a thin host for an already-built boundary
- widget state no longer owns ad-hoc service/repository assembly

## In scope

- `lib/app/discovery_page_entry.dart`
- new composition/boundary factory file(s) under `lib/app/` or another narrow app-layer location
- tests or smokes that cover discovery entry bootstrapping

## Out of scope

- discovery page UI split
- new owner extraction
- shared-cache callback cleanup
- protocol redesign

## Pull Request Cycle

1. Inventory the exact object graph currently built in `DiscoveryPageEntry`.
2. Introduce the explicit boundary factory/composition surface.
3. Move assembly and ownership rules there without changing feature truth.
4. Shrink `DiscoveryPageEntry` to a thin lifecycle host.
5. Run `flutter analyze`, discovery smoke tests, and full `flutter test`.

## Required test gates

- `GATE-03`
- `GATE-08`

## PR1 Inventory Result

### Prerequisite check

- Dependencies are satisfied in the current baseline:
  - `01_local_peer_identity_owner_extraction.md`
  - `04_shared_cache_maintenance_contract_cutover.md`
  - `06_remote_share_media_projection_cleanup.md`
  - `08_transfer_video_link_separation.md`
- PR1 is inventory-only. No production graph extraction is performed here.
- Current owner baseline remains external to `DiscoveryPageEntry`:
  - `SharedCacheCatalog`
  - `SharedCacheIndexStore`
  - `RemoteShareBrowser`
  - `FilesFeatureStateOwner`
  - `PreviewCacheOwner`
  - `TransferSessionCoordinator`
  - `LocalPeerIdentityStore`
  - `SharedCacheMaintenanceBoundary`
  - `VideoLinkSessionBoundary`
  - `RemoteShareMediaProjectionBoundary`

### Production graph assembly inventory

The current production boot path is still:

- `lib/app/app.dart` -> `const DiscoveryPageEntry()`
- `lib/app/router.dart` -> `const DiscoveryPageEntry()`
- `DiscoveryPageEntry.initState()` -> `_buildDiscoveryBoundary()`

Current graph elements assembled inline inside `DiscoveryPageEntry`:

| Element | Kind | Constructed in | Injected into | Current lifecycle owner | Classification |
| --- | --- | --- | --- | --- | --- |
| `AppDatabase.instance` | database handle | `DiscoveryPageEntry._buildDiscoveryBoundary()` | all repository/store constructors | app singleton | app composition dependency |
| `DeviceAliasRepository` | repository | `_buildDiscoveryBoundary()` | `DeviceRegistry`, `TrustedLanPeerStore` | none in widget | app composition dependency |
| `FriendRepository` | repository | `_buildDiscoveryBoundary()` | `InternetPeerEndpointStore` | none in widget | app composition dependency |
| `LocalPeerIdentityStore` | store | `_buildDiscoveryBoundary()` | `DiscoveryController` | none in widget | canonical owner-backed dependency |
| `AppSettingsRepository` | repository | `_buildDiscoveryBoundary()` | `SettingsStore` | none in widget | app composition dependency |
| `SettingsStore` | store | `_buildDiscoveryBoundary()` | `DiscoveryController`, `DiscoveryReadModel`, `SharedCacheMaintenanceBoundary`, `TransferSessionCoordinator` | none in widget | canonical owner-backed dependency |
| `DeviceRegistry` | store | `_buildDiscoveryBoundary()` | `DiscoveryController`, `DiscoveryReadModel`, `TrustedLanPeerStore` | none in widget | canonical owner-backed dependency |
| `InternetPeerEndpointStore` | store | `_buildDiscoveryBoundary()` | `DiscoveryController`, `DiscoveryReadModel` | none in widget | canonical owner-backed dependency |
| `TrustedLanPeerStore` | store | `_buildDiscoveryBoundary()` | `DiscoveryController`, `DiscoveryReadModel`, `TransferSessionCoordinator` trust callback | none in widget | canonical owner-backed dependency |
| `SharedFolderCacheRepository` | repository | `_buildDiscoveryBoundary()` | `SharedCacheCatalog`, `PreviewCacheOwner`, `RemoteShareMediaProjectionBoundary` | none in widget | app composition dependency |
| `SharedCacheIndexStore` | owner/store | `_buildDiscoveryBoundary()` | `DiscoveryController`, `DiscoveryPage`, `SharedCacheCatalog`, `PreviewCacheOwner`, `TransferSessionCoordinator`, `SharedCacheMaintenanceBoundary`, `RemoteShareMediaProjectionBoundary` | none in widget | canonical owner-backed dependency |
| `SharedCacheCatalog` | owner | `_buildDiscoveryBoundary()` | `DiscoveryController`, `DiscoveryPage`, `RemoteShareBrowser`, `TransferSessionCoordinator`, `SharedCacheMaintenanceBoundary`, `RemoteShareMediaProjectionBoundary` | none in widget | canonical owner-backed dependency |
| `FileHashService` | service | `_buildDiscoveryBoundary()` | `DiscoveryController`, `PreviewCacheOwner`, `TransferSessionCoordinator`, `RemoteClipboardProjectionStore`, `RemoteShareMediaProjectionBoundary` | none in widget | app composition dependency |
| `PreviewCacheOwner` | owner | `_buildDiscoveryBoundary()` | `DiscoveryController`, `DiscoveryPage`, `TransferSessionCoordinator` | `DiscoveryPageEntry.dispose()` when self-built | canonical owner-backed dependency plus widget-lifecycle residue |
| `LanDiscoveryService` | service | `_buildDiscoveryBoundary()` | `DiscoveryController`, `TransferSessionCoordinator`, `RemoteShareMediaProjectionBoundary` | indirectly stopped by `DiscoveryController.dispose()` | app composition dependency with mixed lifecycle |
| `FileTransferService` | service | `_buildDiscoveryBoundary()` | `DiscoveryController`, `TransferSessionCoordinator` | none in widget | app composition dependency |
| `TransferHistoryRepository` | repository | `_buildDiscoveryBoundary()` | `DownloadHistoryBoundary`, `DiscoveryController` constructor arg | none in widget | app composition dependency |
| `DownloadHistoryBoundary` | boundary | `_buildDiscoveryBoundary()` | `DiscoveryController`, `DiscoveryPage`, `TransferSessionCoordinator` | indirectly disposed by `DiscoveryController.dispose()` | canonical owner-backed dependency with mixed lifecycle |
| `ClipboardHistoryRepository` | repository | `_buildDiscoveryBoundary()` | `ClipboardHistoryStore`, `DiscoveryController` constructor arg | none in widget | app composition dependency |
| `ClipboardCaptureService` | service | `_buildDiscoveryBoundary()` | `ClipboardHistoryStore`, `DiscoveryController` constructor arg | none in widget | app composition dependency |
| `ClipboardHistoryStore` | owner | `_buildDiscoveryBoundary()` | `DiscoveryController`, `DiscoveryPage` | indirectly disposed by `DiscoveryController.dispose()` | canonical owner-backed dependency with mixed lifecycle |
| `RemoteClipboardProjectionStore` | owner | `_buildDiscoveryBoundary()` | `DiscoveryController`, `DiscoveryPage` | indirectly disposed by `DiscoveryController.dispose()` | canonical owner-backed dependency with mixed lifecycle |
| `RemoteShareBrowser` | owner | `_buildDiscoveryBoundary()` | `DiscoveryController`, `DiscoveryPage`, `TransferSessionCoordinator`, `RemoteShareMediaProjectionBoundary` | `DiscoveryPageEntry.dispose()` when self-built | canonical owner-backed dependency plus widget-lifecycle residue |
| `RemoteShareMediaProjectionBoundary` | boundary | `_buildDiscoveryBoundary()` | `DiscoveryController` | no explicit widget disposal | explicit boundary dependency |
| `VideoLinkShareService` | service | `_buildDiscoveryBoundary()` | `VideoLinkSessionBoundary` | indirectly stopped by `VideoLinkSessionBoundary.dispose()` | app composition dependency with mixed lifecycle |
| `TransferSessionCoordinator` | owner | `_buildDiscoveryBoundary()` | `DiscoveryController`, `DiscoveryPage` | indirectly disposed by `DiscoveryController.dispose()` | canonical owner-backed dependency with mixed lifecycle |
| `DiscoveryController` | controller | `_buildDiscoveryBoundary()` | `DiscoveryReadModel`, `DiscoveryPage`, `VideoLinkSessionBoundary`, `SharedCacheMaintenanceBoundary`, `TransferSessionCoordinator` callbacks | `DiscoveryPageEntry.dispose()` when self-built | widget-local shell construction residue |
| `VideoLinkSessionBoundary` | boundary | `_buildDiscoveryBoundary()` | `DiscoveryPage` | `DiscoveryPageEntry.dispose()` when self-built | explicit boundary dependency plus widget-lifecycle residue |
| `DiscoveryReadModel` | read model | `_buildDiscoveryBoundary()` | `DiscoveryPage` | `DiscoveryPageEntry.dispose()` when self-built | canonical read projection plus widget-lifecycle residue |
| `SharedCacheMaintenanceBoundary` | boundary | `_buildDiscoveryBoundary()` | `DiscoveryPage` | no explicit widget disposal | explicit boundary dependency |
| `TransferStorageService` | UI/app dependency | `DiscoveryPageEntry.initState()` when not injected | `DiscoveryPage`, `ClipboardHistoryStore`, `TransferSessionCoordinator`, `DiscoveryController` | widget field only | widget-lifecycle residue |
| `DesktopWindowService` | UI/app dependency | `DiscoveryPageEntry.initState()` when not injected | `DiscoveryPage`, `_initializeBoundary()` | widget field only | widget-lifecycle residue |
| `_DiscoveryBoundary` | private wrapper | `_buildDiscoveryBoundary()` return value | `_DiscoveryPageEntryState` field assignment only | widget-local | private composition bag / compatibility residue |

### Lifecycle mixing points found

- `State.initState()` decides between injected mode and full inline production assembly, so widget lifecycle and app composition lifecycle are currently fused.
- `_buildDiscoveryBoundary()` assembles the entire discovery screen graph inside widget state instead of outside the host.
- `_initializeBoundary()` mixes controller startup, desktop window side effects, and widget readiness state.
- `DiscoveryPageEntry.dispose()` owns only part of teardown, while `DiscoveryController.dispose()` owns another part, so lifecycle authority is split between host widget and controller shell.
- `TransferStorageService` and `DesktopWindowService` are app/composition dependencies but are currently created and retained as widget-local fields.
- The widget API still exposes dual modes:
  - injected graph mode for tests
  - self-built graph mode for production boot
  This is legitimate for now, but the inline self-built path is still the active production route.

### `_DiscoveryBoundary` classification

- `_DiscoveryBoundary` still exists.
- It is not a runtime owner and does not hold canonical feature truth.
- It is currently a widget-local private graph wrapper that bundles:
  - `DiscoveryController`
  - `DiscoveryReadModel`
  - `RemoteShareBrowser`
  - `SharedCacheMaintenanceBoundary`
  - `VideoLinkSessionBoundary`
  - `SharedCacheCatalog`
  - `SharedCacheIndexStore`
  - `TransferSessionCoordinator`
  - `DownloadHistoryBoundary`
  - `ClipboardHistoryStore`
  - `RemoteClipboardProjectionStore`
  - `PreviewCacheOwner`
- In practice it is a lifecycle wrapper / service bag residue, not a legitimate long-term boundary.

### Production composition vs test/support coupling

- Production composition:
  - `app.dart` and `router.dart` both boot the app with `const DiscoveryPageEntry()`
  - therefore `_buildDiscoveryBoundary()` is still the real production graph assembly path
- Test/support coupling:
  - `test/smoke_test.dart` covers two entry flows:
    - direct `DiscoveryPage` with fully injected dependencies
    - `DiscoveryPageEntry` with an injected graph and controller startup
  - `test/test_support/test_discovery_controller.dart` manually recreates almost the same graph as `_buildDiscoveryBoundary()` for harness convenience
- These tests encode bootstrap and injected-host behavior, but they should not define production architecture. PR2 will need to update them to the new composition route without restoring widget-local assembly.

### PR2 seam contract

Legacy owner / legacy route:

- inline discovery graph assembly inside `DiscoveryPageEntry._buildDiscoveryBoundary()`
- widget-local dependency retention in `_DiscoveryPageEntryState`
- widget-owned readiness/startup path in `_initializeBoundary()`
- split disposal between `DiscoveryPageEntry.dispose()` and `DiscoveryController.dispose()`
- `_DiscoveryBoundary` as a widget-local private service bag

Target owner / target boundary:

- explicit discovery composition factory / composition result object outside widget state
- narrow app-layer composition surface only
- allowed responsibilities:
  - build the discovery screen graph
  - define explicit start/dispose ownership for the assembled graph
  - return typed dependencies needed by `DiscoveryPageEntry`
- forbidden responsibilities:
  - owning runtime truth
  - becoming a mutable service bag
  - becoming a new god-object factory for arbitrary app concerns
- `DiscoveryPageEntry` must become a thin host only

Read switch point:

- `DiscoveryPageEntry.build()` must stop reading a widget-local graph produced by `_buildDiscoveryBoundary()`
- dependency access should instead come from an explicit composition result created outside widget state

Write switch point:

- `DiscoveryPageEntry._buildDiscoveryBoundary()` must stop constructing repositories, services, owners, boundaries, read model, and controller inline on the production boot path
- production boot through `app.dart` / `router.dart` must stop relying on widget-local graph assembly

Forbidden writers:

- `DiscoveryPageEntry`
- `DiscoveryPage`
- widgets
- repositories
- helper facades or service bags acting as hidden composition owners

Forbidden dual-write paths:

- inline `DiscoveryPageEntry` graph assembly plus new factory both active on the production boot path
- widget-local `_DiscoveryBoundary` plus new factory both acting as active composition owners
- split lifecycle/dispose ownership between old widget-local graph and new factory result without one explicit owner

Expected consumers of the future factory/composition boundary:

- `DiscoveryPageEntry` as thin host only
- `DiscoveryPage`
- `DiscoveryController`
- all already-extracted owners and boundaries injected into the discovery screen graph
- smoke tests and harnesses that bootstrap discovery entry

Files PR2 will need to change:

Must change:

- `lib/app/discovery_page_entry.dart`
- a new discovery composition/factory file under `lib/app/`

Likely change:

- `lib/app/app.dart`
- `lib/app/router.dart`
- `test/smoke_test.dart`
- `test/test_support/test_discovery_controller.dart`

### PR1 conclusion

- PR2 is unblocked.
- The extraction target is explicit enough for a non-speculative cutover.
- No blocker from `03_discovery_page_surface_split.md` or `05_files_part_graph_removal.md` was found.
- The seam definition keeps extracted owners external and authoritative.
- The key PR2 constraint is architectural honesty:
  - move graph assembly and lifecycle ownership out of widget state
  - do not replace `DiscoveryPageEntry` with another mutable service bag or god-object factory

## Completion proof

- `DiscoveryPageEntry` no longer assembles the full discovery graph inline
- `_DiscoveryBoundary` is deleted or reduced to a thin value object outside widget state
- entry flow still boots correctly under smoke tests
- analyzer and tests stay green
