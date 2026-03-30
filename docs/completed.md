# Completed Refactor Status

Этот файл фиксирует, какие части плана из `docs/*.md` уже выполнены по текущему состоянию репозитория.

Источники:

- `docs/refactor_master_plan.md`
- `docs/refactor_workpacks/00_index.md`
- `docs/refactor_workpacks/18_deletion_wave_map.md`
- текущее состояние `lib/` и `test/`

## 1. Уже завершенный baseline из master plan

Из `docs/refactor_master_plan.md`, раздел `Current Baseline`, уже считаются выполненными и не должны переоткрываться как незакрытые seams:

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

## 2. Завершенные workpack-файлы

На текущий момент выполнены следующие workpack’и из `docs/refactor_workpacks/`:

- `01_local_peer_identity_owner_extraction.md`
  - локальная peer identity больше не принадлежит `FriendRepository`
- `02_discovery_boundary_factory_extraction.md`
  - сборка discovery graph вынесена из widget lifecycle в app-layer composition
- `03_discovery_page_surface_split.md`
  - гигантский `DiscoveryPage` уже разрезан на отдельные presentation surfaces
- `04_shared_cache_maintenance_contract_cutover.md`
  - удален bridge/backchannel shared-cache maintenance seam
- `05_files_part_graph_removal.md`
  - files presentation больше не использует `part / part of`
- `06_remote_share_media_projection_cleanup.md`
  - controller-side thumbnail/media IO выведен в явную boundary
- `08_transfer_video_link_separation.md`
  - video-link flow отделен от transfer shell concerns

## 3. Что именно уже удалено или минимизировано по deletion wave map

Из `docs/refactor_workpacks/18_deletion_wave_map.md` уже выполнены такие пункты:

- `FriendRepository.loadOrCreateLocalPeerId()` как business owner `local_peer_id`
- `DiscoveryPageEntry._DiscoveryBoundary` и page-local graph assembly
- `SharedCacheCatalogBridge`
- `DiscoveryPage -> FileExplorerPage.launch(...)` recache/remove/progress callback bundle
- files `part / part of` cluster under `file_explorer_page.dart`
- controller-side thumbnail IO through `SharedFolderCacheRepository`
- manual `RemoteShareBrowser` notification nudges from controller glue
- mixed transfer/watch-link routing between discovery shells and `VideoLinkShareService`
- monolithic `DiscoveryPage` section and modal bodies materially reduced

## 4. Какие волны уже фактически закрыты

- Wave A: завершена
  - `01`, `04`, `08`
- Wave B: завершена
  - `06`, `02`, `05`
- Wave C: выполнена частично
  - завершен `03`
  - еще остаются `07` и `09`
- Wave D: еще не выполнена
  - `10`

## 5. Что еще остается невыполненным из текущего плана

По `docs/refactor_master_plan.md` и `docs/refactor_workpacks/00_index.md` еще остаются открытыми:

- `07_shared_folder_cache_repository_split.md`
- `09_protocol_codec_family_decomposition.md`
- `10_architecture_guard_and_regression_hardening.md`

## 6. Короткая сводка по состоянию плана

Уже закрыты:

- owner cleanup для local peer identity
- shared-cache maintenance cutover
- remote-share media projection cleanup
- transfer/video-link separation
- discovery composition factory extraction
- files presentation `part` graph removal
- discovery page surface split

Еще не закрыты:

- repository split (`07`)
- protocol codec decomposition (`09`)
- architecture guards / regression hardening (`10`)
