# Deletion Wave Map

Derived from `docs/refactor_master_plan.md` and `docs/refactor_workpacks/00_index.md`.

| Artifact or residue | Deleted or minimized by | Earliest wave | Deletion condition | Proof required (current baseline) |
| --- | --- | --- | --- | --- |
| `FriendRepository.loadOrCreateLocalPeerId()` as business owner of `local_peer_id` | `01` | Wave A | local peer ID owned by `LocalPeerIdentityStore` only | `test/local_peer_identity_store_test.dart`, `test/discovery_controller_settings_store_test.dart`, `GATE-08` |
| `DiscoveryPageEntry` widget-local graph assembly | `02` | Wave B | graph built by `lib/app/discovery/discovery_composition.dart` | `test/smoke_test.dart`, `GATE-08` |
| `SharedCacheCatalogBridge` | `04` | Wave A | bridge removed; no references in `lib/` | `test/architecture_guard_test.dart`, `GATE-08` |
| discovery/files recache/remove/progress callback bundle | `04` | Wave A | files maintenance uses `SharedCacheMaintenanceBoundary` | `test/architecture_guard_test.dart`, `test/blocked_entry_flow_regression_test.dart`, `GATE-08` |
| files `part / part of` under `file_explorer_page.dart` | `05` | Wave B | no `part / part of` under `lib/` | `test/architecture_guard_test.dart`, `GATE-08` |
| controller-side thumbnail IO through `SharedFolderCacheRepository` | `06` | Wave B | thumbnail IO goes through `RemoteShareMediaProjectionBoundary` + thumbnail store | `test/remote_share_media_projection_boundary_test.dart`, `test/preview_cache_owner_test.dart`, `GATE-08` |
| manual `RemoteShareBrowser` notify glue | `06` | Wave B | media projection updates owned by boundary, not controller | `test/remote_share_media_projection_boundary_test.dart`, `GATE-08` |
| `SharedFolderCacheRepository` as broad do-everything repository | `07` | Wave C | repository reduced to `SharedCacheRecordStore` only | `test/shared_folder_cache_repository_test.dart`, `test/shared_cache_catalog_test.dart`, `GATE-08` |
| thumbnail artifact IO inside broad repository | `07` | Wave C | thumbnail IO via `SharedCacheThumbnailStore` | `test/preview_cache_owner_test.dart`, `test/remote_share_media_projection_boundary_test.dart`, `GATE-08` |
| mixed transfer/watch-link routing in discovery shell | `08` | Wave A | video-link flow routed via `VideoLinkSessionBoundary` | `test/video_link_session_boundary_test.dart`, `test/transfer_session_coordinator_test.dart`, `GATE-08` |
| monolithic `DiscoveryPage` section and modal bodies | `03` | Wave C | page split into dedicated presentation files | `test/smoke_test.dart`, `GATE-08` |
| monolithic `lan_packet_codec.dart` family surface | `09` | Wave C | family codec files + `lan_packet_codec_models.dart` + `lan_packet_codec_common.dart` | `test/lan_packet_codec_test.dart`, `test/lan_discovery_service_*`, `GATE-08` |
| missing architecture guardrails for bridges, callback backchannels, and `part` regressions | `10` | Wave D | dedicated guard suite exists | `test/architecture_guard_test.dart`, `GATE-08` |
| weak entry-flow coverage for post-refactor surfaces | `10` | Wave D | UI regressions covered for all weak flows | `test/smoke_test.dart`, `test/blocked_entry_flow_regression_test.dart`, `GATE-08` |
