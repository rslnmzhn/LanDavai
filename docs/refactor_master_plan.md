# Refactor Master Plan

## 1. Purpose

Этот документ заменяет закрытый tactical backlog в `docs/`.
Он фиксирует новую post-refactor baseline и новый список remaining refactor zones.
Задача этого плана не повторять уже выполненные ownership splits, а описать то, что все еще требует архитектурной работы:

- lingering god-classes and god-modules
- surviving temporary bridges and callback residue
- `part / part of` clusters
- direct repository bypasses around extracted owners
- zones of double responsibility and unclear contracts
- testing and architecture-guard gaps that still allow backslides

Scope:

- `lib/`
- `test/`
- `docs/`

Out of scope:

- platform folders outside Dart surface
- protocol or storage semantics changes unless a specific workpack says they are required
- redoing already-completed owner seams as if they were unfinished

## 2. Current Baseline

Completed seams that are now baseline and must not be re-opened casually:

- `DiscoveryReadModel` owns the discovery-facing read projection
- `SharedCacheCatalog` owns shared-cache metadata truth
- `SharedCacheIndexStore` owns shared-cache index truth
- `RemoteShareBrowser` owns remote share browse/session truth
- `FilesFeatureStateOwner` owns explorer navigation/view truth
- `PreviewCacheOwner` owns preview lifecycle and cache truth
- `TransferSessionCoordinator` owns live transfer/session truth
- `DownloadHistoryBoundary` owns download history truth
- `ClipboardHistoryStore` owns local clipboard history truth
- `RemoteClipboardProjectionStore` owns remote clipboard projection truth

These are foundation, not new migration targets.
New work must not silently move their truth back into:

- `DiscoveryController`
- `DiscoveryPage`
- widgets
- repositories
- temporary facades or callback bundles

## 3. Remaining Refactor Zones

| Zone | Current evidence | Why it still matters | Target direction | Planned workpack |
| --- | --- | --- | --- | --- |
| Local peer identity still lives in `FriendRepository` | `DiscoveryController.start()` still calls `FriendRepository.loadOrCreateLocalPeerId()`; `local_peer_id` still lives behind friend semantics | local identity and friend endpoint ownership are still mixed | extract a narrow local-peer-identity boundary and stop using `FriendRepository` as the business owner of `local_peer_id` | `01_local_peer_identity_owner_extraction.md` |
| `DiscoveryPageEntry` is still a composition-root god-module | `DiscoveryPageEntry` constructs database, repositories, services, owners, controller, and `_DiscoveryBoundary` directly | app composition and widget lifecycle are still over-coupled; testing and reuse stay expensive | move discovery boundary assembly into a dedicated factory/root outside the widget shell | `02_discovery_boundary_factory_extraction.md` |
| `DiscoveryPage` remains a giant screen shell | `DiscoveryPage` is still the biggest UI file in the repo and still holds large modal/section bodies | large UI diffs still carry high regression radius even after owner extraction | split the page into smaller screen sections and feature-entry surfaces without re-centralizing state | `03_discovery_page_surface_split.md` |
| Shared-cache maintenance still has a backchannel seam | `SharedCacheCatalogBridge` is still alive; `DiscoveryPage -> FileExplorerPage.launch(...)` still passes recache/remove/progress callbacks and listenables | final callback cleanup was not actually complete for files/shared-cache flows | cut over to an explicit shared-cache maintenance contract and delete the bridge/backchannel bundle | `04_shared_cache_maintenance_contract_cutover.md` |
| Files presentation still uses `part / part of` | `file_explorer_page.dart` still owns a `part` graph for viewer, widgets, models, and recache status | ownership is no longer hidden there, but the module is still hard to change safely and easy to regress into hidden coupling | remove the `part` graph and split the files presentation into explicit leaf modules | `05_files_part_graph_removal.md` |
| Remote-share media and thumbnail flow still bypasses owners | `DiscoveryController` still performs thumbnail IO via `SharedFolderCacheRepository` and manually nudges `RemoteShareBrowser` after updates | remote-share media projection is still partly routed through controller/repository glue | move thumbnail/media projection updates behind an explicit boundary owned by `RemoteShareBrowser` or a narrow collaborator | `06_remote_share_media_projection_cleanup.md` |
| `SharedFolderCacheRepository` remains a god-repository | it still mixes DB record IO, JSON index IO, indexing, pruning, thumbnail artifact IO, and selection-cache helpers | extracted owners still depend on a broad infra class with multiple reasons to change | split repository responsibilities under narrower data collaborators and ports | `07_shared_folder_cache_repository_split.md` |
| Transfer flow and video-link flow are still too close | `TransferSessionCoordinator` is large, `VideoLinkShareService.activeSession` remains separate, and discovery/page shells still mix transfer and watch-link entry concerns | video-link session residue can pull transfer coordination back into a broad shell | keep transfer coordinator narrow and extract a cleaner video-link boundary/entry flow | `08_transfer_video_link_separation.md` |
| Protocol codec surface and guardrails are still weak | `lan_packet_codec.dart` is still large; there is no strong guard suite that rejects new bridges, callback lattices, or `part`-based ownership regressions | post-refactor architecture can still drift back without explicit proof | split codec families where useful and add architecture/regression guards that fail on backslides | `09_protocol_codec_family_decomposition.md`, `10_architecture_guard_and_regression_hardening.md` |

## 4. Priority Order

Recommended execution order:

1. `01_local_peer_identity_owner_extraction.md`
2. `04_shared_cache_maintenance_contract_cutover.md`
3. `06_remote_share_media_projection_cleanup.md`
4. `08_transfer_video_link_separation.md`
5. `02_discovery_boundary_factory_extraction.md`
6. `05_files_part_graph_removal.md`
7. `07_shared_folder_cache_repository_split.md`
8. `03_discovery_page_surface_split.md`
9. `09_protocol_codec_family_decomposition.md`
10. `10_architecture_guard_and_regression_hardening.md`

Rationale:

- first remove the most obvious ownership and callback residue
- then shrink widget and composition shells
- then split broad infra and protocol modules
- then lock the architecture with dedicated guardrails

## 5. Migration Rules

Rules for every remaining workpack:

- Do not re-open already-extracted owner seams unless the workpack is explicitly tightening their contract.
- Do not move truth back into `DiscoveryController`, `DiscoveryPage`, widgets, or repositories.
- Do not introduce a new long-lived bridge, facade, or callback bundle without a same-plan deletion phase.
- Do not use `part / part of` to fake modularity in critical seams.
- Prefer deleting obsolete compatibility surfaces over renaming them.
- Keep packet identifiers, storage schema, and persisted data semantics stable unless a workpack explicitly says otherwise.
- Treat `VideoLinkShareService.activeSession` as its own seam until a dedicated workpack proves otherwise.

## 6. Done vs Remaining

What is done:

- tactical owner extraction for discovery reads, shared cache, remote browse, files state, preview lifecycle, transfer sessions, download history, and clipboard history/projection

What remains:

- shell decomposition
- maintenance contract cleanup
- data-layer decomposition
- local peer identity cleanup
- remote-share media contract cleanup
- video-link separation
- guardrail hardening

## 7. Completion Standard

This new refactor plan can be considered materially complete only when:

- no surviving temporary bridge or callback backchannel remains on production paths
- remaining large modules are narrowed to one primary reason to change
- `DiscoveryController` and `DiscoveryPage` are no longer giant routing shells
- no critical feature seam relies on `part / part of`
- direct repository bypasses around extracted owners are gone
- architecture guard tests and regression smoke tests lock these boundaries in place
- `flutter analyze` and `flutter test` stay green
