# Workpack 10: Architecture Guard and Regression Hardening

## Purpose

Turn the post-refactor architecture into an enforceable baseline by adding dedicated guard tests and restoring weak or missing entry-flow coverage.

## Why This Exists Now

Current evidence:

- there is no strong automated guard against reintroducing:
  - temporary bridges
  - callback backchannels
  - critical `part / part of` seams
  - direct repository bypasses around extracted owners
- some critical feature-entry proof still relies mainly on smoke coverage and full-suite confidence

## In Scope

- architecture guard tests
- widget/smoke coverage for discovery, files, clipboard, history, and remote-share entry flows touched by the new plan
- documentation or test helpers needed to keep guardrails cheap to run

## Out of Scope

- new owner extraction
- protocol or storage contract changes
- product UX redesign

## Target State

- prohibited architectural patterns fail fast in tests
- critical entry flows have explicit regression coverage
- future work cannot quietly reintroduce bridges, callback lattices, or hidden ownership hubs

## Pull Request Cycle

1. Inventory the architectural patterns that must now stay forbidden.
2. Add targeted guard tests and restore weak entry-flow coverage.
3. Delete obsolete test assumptions tied to the old tactical backlog.
4. Run the full suite, then `flutter analyze` and `flutter test`.

## Dependencies

- `01_local_peer_identity_owner_extraction.md`
- `03_discovery_page_surface_split.md`
- `04_shared_cache_maintenance_contract_cutover.md`
- `05_files_part_graph_removal.md`
- `06_remote_share_media_projection_cleanup.md`
- `07_shared_folder_cache_repository_split.md`
- `08_transfer_video_link_separation.md`
- `09_protocol_codec_family_decomposition.md`

## Required Test Gates

- `GATE-07`
- `GATE-08`

## Completion Proof

- dedicated guard tests fail on prohibited bridges, callback lattices, `part` regressions, and owner bypasses
- critical entry-flow coverage is explicit instead of implied
- full suite remains green

## PR1 Inventory Result

PR1 for this workpack is inventory-only.
No architecture guard tests or widget/smoke expansions land here.
The purpose of this note is to freeze the exact forbidden-pattern map and weak-entry-flow map so PR2 and PR3 can execute without re-inventory.

### Prerequisite confirmation

- Dependency seams are satisfied in current code:
  - `01_local_peer_identity_owner_extraction.md`
  - `03_discovery_page_surface_split.md`
  - `04_shared_cache_maintenance_contract_cutover.md`
  - `05_files_part_graph_removal.md`
  - `06_remote_share_media_projection_cleanup.md`
  - `07_shared_folder_cache_repository_split.md`
  - `08_transfer_video_link_separation.md`
  - `09_protocol_codec_family_decomposition.md`
- Current baseline evidence in `lib/`:
  - `DiscoveryController` reads local peer identity via `LocalPeerIdentityStore`
  - `DiscoveryPage` is split into dedicated presentation surfaces
  - files entry uses `SharedCacheMaintenanceBoundary` instead of the old callback bundle
  - no `part / part of` remains under `lib/`
  - remote-share thumbnail/media projection routes through `RemoteShareMediaProjectionBoundary`
  - `SharedFolderCacheRepository` is thin row IO only
  - video-link UI routes through `VideoLinkSessionBoundary`
  - protocol family logic lives outside `lan_packet_codec.dart`

### Existing coverage baseline

Current real proof already in the repo:

- `GATE-08` baseline:
  - `flutter analyze`
  - `flutter test`
- discovery/files/widget proof:
  - `test/smoke_test.dart`
  - `test/files_presentation_import_test.dart`
- owner/boundary proof:
  - `test/local_peer_identity_store_test.dart`
  - `test/shared_cache_catalog_test.dart`
  - `test/shared_cache_index_store_test.dart`
  - `test/shared_cache_maintenance_boundary_test.dart`
  - `test/preview_cache_owner_test.dart`
  - `test/remote_share_browser_test.dart`
  - `test/remote_share_media_projection_boundary_test.dart`
  - `test/remote_clipboard_projection_store_test.dart`
  - `test/download_history_boundary_test.dart`
  - `test/video_link_session_boundary_test.dart`
- protocol proof:
  - `test/lan_packet_codec_test.dart`
  - `test/lan_discovery_service_contract_test.dart`
  - `test/lan_discovery_service_packet_codec_test.dart`
  - `test/lan_discovery_service_protocol_handlers_test.dart`
  - `test/lan_discovery_service_transport_adapter_test.dart`

Current missing proof:

- no dedicated `GATE-07` architecture guard suite exists yet
- widget/smoke proof is discovery-heavy and still weak for several post-refactor entry flows

### Forbidden-pattern inventory

#### 1. Bridge reintroduction

Exact regression target:

- `SharedCacheCatalogBridge`

Where it could regress:

- `lib/features/discovery/application/`
- `lib/features/discovery/presentation/`
- `lib/features/files/presentation/`

Realistic PR2 static/source-scan proof:

- fail if `SharedCacheCatalogBridge` appears anywhere under `lib/`

Behavior-level proof also needed:

- no; this is a static residue ban, not a UI behavior question

#### 2. Shared-cache callback backchannel reintroduction

Exact regression targets:

- `onRecacheSharedFolders`
- `onRemoveSharedCache`
- `recacheStateListenable`

Where it could regress:

- `lib/features/discovery/presentation/discovery_page.dart`
- `lib/features/files/presentation/file_explorer_page.dart`

Realistic PR2 static/source-scan proof:

- fail if those exact symbols reappear under `lib/`
- fail if `DiscoveryPage` resumes acting as the files/shared-cache maintenance relay

Behavior-level proof also needed:

- yes
- `FileExplorerPage.launch(...)` survivability still needs behavior proof in PR3 because static scanning cannot prove the post-cutover UI route still works

#### 3. `part / part of` regressions

Exact regression targets:

- `^part '`
- `part of`

Where it could regress:

- all critical seams under `lib/`

Realistic PR2 static/source-scan proof:

- fail if either pattern appears anywhere under `lib/`

Behavior-level proof also needed:

- no

#### 4. Owner-bypass regressions

##### 4a. Local peer identity bypass

Exact regression targets:

- `loadOrCreateLocalPeerId(` outside `local_peer_identity_store.dart`
- `DiscoveryController` importing `friend_repository.dart`

Where it could regress:

- `lib/features/discovery/application/discovery_controller.dart`
- other discovery startup/composition paths

Realistic PR2 static/source-scan proof:

- fail if `loadOrCreateLocalPeerId(` appears outside `lib/features/discovery/application/local_peer_identity_store.dart`
- fail if `lib/features/discovery/application/discovery_controller.dart` imports `friend_repository.dart`

Behavior-level proof also needed:

- no beyond existing store/controller tests

##### 4b. Remote-share media controller IO bypass

Exact regression targets:

- `readOwnerThumbnailBytes(`
- `resolveReceiverThumbnailPath(`
- `saveReceiverThumbnailBytes(`

Where it could regress:

- `lib/features/discovery/application/discovery_controller.dart`

Realistic PR2 static/source-scan proof:

- fail if those methods appear in `DiscoveryController`
- fail if `DiscoveryController` imports `thumbnail_cache_service.dart` or `shared_folder_cache_repository.dart`

Behavior-level proof also needed:

- yes
- remote-share thumbnail visibility and preview launch still need PR3 regression proof

##### 4c. Shared-cache row-path coupling regression

Exact regression targets:

- `SharedCacheCatalog` depending on `SharedFolderCacheRepository` instead of `SharedCacheRecordStore`

Where it could regress:

- `lib/features/transfer/application/shared_cache_catalog.dart`

Realistic PR2 static/source-scan proof:

- fail if `shared_cache_catalog.dart` imports `shared_folder_cache_repository.dart`
- fail if `shared_cache_catalog.dart` stops depending on `SharedCacheRecordStore`

Behavior-level proof also needed:

- no beyond existing shared-cache tests

##### 4d. Controller-side video-link mirror/command regression

Exact regression targets:

- `_videoLinkShareSession`
- `videoLinkWatchUrl`
- `publishVideoLinkShare(`
- `stopVideoLinkShare(`

Where it could regress:

- `lib/features/discovery/application/discovery_controller.dart`

Realistic PR2 static/source-scan proof:

- fail if those exact controller-side symbols reappear

Behavior-level proof also needed:

- yes
- side-menu video-link survivability is a UI flow, not just a static dependency question

#### 5. God-module regression targets

##### 5a. `shared_folder_cache_repository.dart` broadening

Exact regression targets:

- deleted broad methods must not return:
  - `buildOwnerCache(`
  - `upsertOwnerFolderCache(`
  - `buildOwnerSelectionCache(`
  - `saveReceiverCache(`
  - `refreshOwnerSelectionCacheEntries(`
  - `refreshOwnerFolderSubdirectoryEntries(`
  - `deleteCache(`
  - `pruneUnavailableOwnerCaches(`
  - `pruneReceiverCachesForOwner(`

Where it could regress:

- `lib/features/transfer/data/shared_folder_cache_repository.dart`

Realistic PR2 static/source-scan proof:

- fail if any of those method names reappear in the repository file

Behavior-level proof also needed:

- no beyond existing shared-cache and remote-share tests

##### 5b. `lan_packet_codec.dart` re-expansion

Exact regression target:

- `lan_packet_codec.dart` must stay a thin facade, not become DTO or family-logic truth again

Where it could regress:

- `lib/features/discovery/data/lan_packet_codec.dart`
- protocol-internal files under `lib/features/discovery/data/`

Realistic PR2 static/source-scan proof:

- fail if protocol-internal files route DTO/constant truth back through `lan_packet_codec.dart` where direct `common/models` imports are the current baseline
- keep app-layer imports out of scope; this workpack should not force broad caller churn

Behavior-level proof also needed:

- no beyond existing protocol compatibility tests

##### 5c. `lan_packet_codec_common.dart` overgrowth

Exact regression targets:

- family-specific parsing/encoding must not drift into `lan_packet_codec_common.dart`
- DTO declarations must not drift into `lan_packet_codec_common.dart`

Where it could regress:

- `lib/features/discovery/data/lan_packet_codec_common.dart`

Realistic PR2 static/source-scan proof:

- fail if `lan_packet_codec_common.dart` declares packet DTO classes
- fail if it declares family-specific methods such as:
  - `parse*Packet`
  - `encodeTransfer*`
  - `encodeFriend*`
  - `encodeShare*`
  - `encodeThumbnail*`
  - `encodeClipboard*`
  - `fitShareCatalogEntries`

Behavior-level proof also needed:

- no beyond existing protocol compatibility tests

#### 6. Dual-truth / dual-route regressions

Exact regression targets:

- `LocalPeerIdentityStore` vs old `FriendRepository` path
- `SharedCacheMaintenanceBoundary` vs callback bundle path
- `RemoteShareMediaProjectionBoundary` vs controller thumbnail IO path
- `VideoLinkSessionBoundary` vs controller-side video-link mirror
- family codec split vs monolithic codec logic returning as parallel truth

Where it could regress:

- discovery application shell
- files/discovery presentation seam
- transfer data/application seam
- protocol layer

Realistic PR2 static/source-scan proof:

- combine the exact bans above into one guard suite
- do not invent a generic “dual truth” regex with no concrete anchors

Behavior-level proof also needed:

- yes where the old route was user-visible:
  - files/shared-cache entry
  - remote-share browse/preview
  - side-menu video-link flow

### Weak-entry-flow inventory

Flows where current explicit regression proof is weak:

- discovery settings sheet entry
  - current proof: none at widget level
  - current risk: shell regression after page split
- discovery clipboard sheet entry
  - current proof: owner/unit tests only
  - current risk: entry survives in owners but sheet launch breaks
- discovery history sheet entry
  - current proof: `DownloadHistoryBoundary` unit tests only
  - current risk: entry wiring breaks without failing owner tests
- discovery files launch
  - current proof: `files_presentation_import_test.dart` proves constructibility only
  - current risk: navigation/screen launch can break while imports still compile
- discovery device actions menu
  - current proof: none at widget level
  - current risk: extracted menu/dialog launch regresses silently
- discovery side-menu video-link survivability
  - current proof: `VideoLinkSessionBoundary` and service unit tests only
  - current risk: UI shell survives compile-time but not user interaction
- remote-share catalog/thumbnail visibility and preview/viewer launch
  - current proof: owner/boundary tests plus receive-sheet open in `smoke_test.dart`
  - current risk: projection state works but UI entry/preview route breaks
- files/viewer entry survivability
  - current proof: constructibility only
  - current risk: viewer launch/render path regresses
- shared-cache recache/remove UI entry after backchannel removal
  - current proof: maintenance boundary tests only
  - current risk: boundary remains correct while files UI entry path drifts

Current widget/smoke proof already present:

- `DiscoveryPage` render
- `DiscoveryPageEntry` startup
- receive-flow sheet open
- friends sheet open

### PR2 seam contract: architecture guard tests

Legacy risk / legacy route:

- no automated guard currently fails when deleted architectural residue returns
- current protection is mostly code review plus broad regression confidence

Target guard / target proof:

- dedicated `GATE-07` static/source-scan architecture tests
- fail fast on exact forbidden symbols, imports, and residue routes listed above

Read switch point:

- source-scan over `lib/`
- first mandatory checks:
  - `SharedCacheCatalogBridge`
  - `part / part of`
  - old shared-cache callback bundle symbols
  - local peer identity bypass path
  - remote-share media controller IO path
  - controller-side video-link mirror path
  - broad repository method resurrection
  - protocol common/shell overreach

Write switch point:

- new test file or test cluster under `test/` dedicated to architecture guards

Forbidden writers:

- production files trying to reintroduce deleted residue
- test helpers that normalize temporary residue as approved baseline

Forbidden dual-write paths:

- broad generic scans with false positives
- behavior tests pretending to be architecture proof without exact static anchors
- architecture scans that silently widen into new production refactor work

Expected PR2 targets:

- new architecture guard test file(s) under `test/`
- likely helper utilities for source scanning under `test/` only if needed

### PR3 seam contract: regression hardening

Legacy risk / legacy route:

- several post-refactor entry flows still rely on owner/unit proof and broad full-suite confidence instead of explicit UI regression checks

Target guard / target proof:

- widget/smoke coverage that proves the weak flows above still open, render, and survive user entry

Read switch point:

- current discovery-heavy smoke baseline

Write switch point:

- `test/smoke_test.dart`
- new focused widget/smoke tests only if `smoke_test.dart` would become too broad

Forbidden writers:

- production code changed only to make tests easier
- tests overfitting to file layout instead of user-visible behavior
- tests that silently re-encode old tactical backlog assumptions

Forbidden dual-write paths:

- keeping weak constructor/import proof while claiming it replaces missing widget coverage
- adding redundant UI tests that lock internal widget/file structure instead of behavior

Expected PR3 targets:

- discovery launch surfaces:
  - settings
  - clipboard
  - history
  - files
  - device actions
  - video-link side-menu survivability
- remote-share receive/browse/preview flows
- files/viewer launch survivability
- shared-cache recache/remove UI entry survivability

### Non-goals and false-positive traps

Do not freeze or implement these as workpack-10 rules:

- generic “all callbacks are forbidden”
- generic “all bridge strings are forbidden”
- generic “all data-layer imports are forbidden”
- file-size or line-count heuristics pretending to prove architecture health
- `notifyListeners()` count checks
- broad bans on composition-layer concrete imports such as `discovery_composition.dart`
- blanket bans on `LanPacketCodec` imports from app-layer consumers; current honest baseline still allows that compatibility facade

### PR1 conclusion

- PR2 is unblocked.
- PR3 is unblocked.
- The forbidden-pattern map is explicit enough for dedicated static/source-scan guard tests.
- The weak-entry-flow map is explicit enough for dedicated widget/smoke regression proof.
- No production code or test behavior changed in PR1.
