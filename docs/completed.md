# Completed Refactor Status

Этот файл фиксирует, какие части плана из `docs/*.md` уже выполнены по текущему
состоянию репозитория.

Источники:

- `docs/refactor_master_plan.md`
- `docs/refactor_workpacks/00_index.md`
- `docs/refactor_workpacks/18_deletion_wave_map.md`
- текущее состояние `lib/` и `test/`

## 1. Пост-рефактор baseline (не открывать заново)

- `DiscoveryReadModel` owns the discovery-facing read projection
- `LocalPeerIdentityStore` owns local peer identity persistence/creation
- `SharedCacheCatalog` owns shared-cache metadata truth
- `SharedCacheIndexStore` owns shared-cache index truth
- `SharedCacheMaintenanceBoundary` owns recache/remove/progress
- `RemoteShareBrowser` owns remote share browse/session truth
- `RemoteShareMediaProjectionBoundary` owns remote-share thumbnail/media projection
- `FilesFeatureStateOwner` owns explorer/navigation/view truth
- `PreviewCacheOwner` owns preview lifecycle/cache truth
- `TransferSessionCoordinator` owns live transfer/session truth
- `VideoLinkSessionBoundary` owns video-link session commands + projection
- `DownloadHistoryBoundary` owns download history truth
- `ClipboardHistoryStore` owns local clipboard history truth
- `RemoteClipboardProjectionStore` owns remote clipboard projection truth

## 2. Завершенные workpack-файлы (01–09)

Выполнены и подтверждены кодом:

- `01_local_peer_identity_owner_extraction.md`
  - `LocalPeerIdentityStore` owns `local_peer_id`
  - `FriendRepository` no longer owns local identity
- `02_discovery_boundary_factory_extraction.md`
  - composition lives in `lib/app/discovery/discovery_composition.dart`
- `03_discovery_page_surface_split.md`
  - `DiscoveryPage` split into dedicated presentation surfaces
- `04_shared_cache_maintenance_contract_cutover.md`
  - `SharedCacheMaintenanceBoundary` is in use
  - bridge/callback bundle removed
- `05_files_part_graph_removal.md`
  - no `part / part of` under files presentation
- `06_remote_share_media_projection_cleanup.md`
  - thumbnail/media IO via `RemoteShareMediaProjectionBoundary`
  - controller IO bypass removed
- `07_shared_folder_cache_repository_split.md`
  - `SharedFolderCacheRepository` reduced to thin `SharedCacheRecordStore`
  - thumbnail IO via `SharedCacheThumbnailStore`
- `08_transfer_video_link_separation.md`
  - `VideoLinkSessionBoundary` separated
  - controller/page no longer own video-link session
- `09_protocol_codec_family_decomposition.md`
  - protocol family codecs split into dedicated files
  - DTOs in `lan_packet_codec_models.dart`
  - common helpers in `lan_packet_codec_common.dart`
  - `LanPacketCodec` is a thin facade

## 3. Workpack 10 status

`10_architecture_guard_and_regression_hardening.md` is completed.

Completion proof:

- PR1 inventory freeze (documented)
- PR2 architecture guard tests exist:
  - `test/architecture_guard_test.dart`
- PR3 stable entry-flow coverage exists in:
  - `test/smoke_test.dart`
- UI proof for shared-cache recache/remove:
  - `test/blocked_entry_flow_regression_test.dart`
- UI proof for the remaining weak flows:
  - `test/files_entry_flow_regression_test.dart`
  - `test/remote_share_viewer_flow_regression_test.dart`
  - `test/history_entry_flow_regression_test.dart`

## 4. Deletion wave status

Waves A–D are complete (01–10).
