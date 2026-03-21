# Refactor Workpacks Fix Summary

## 1. Files added

- `docs/refactor_workpacks/03a_phase_1_internet_peer_endpoint_store_activation.md`
- `docs/refactor_workpacks/03b_phase_1_settings_store_activation.md`
- `docs/refactor_workpacks/13a_phase_6_remote_clipboard_projection_extraction.md`
- `docs/refactor_workpacks/13b_phase_6_download_history_extraction.md`

## 2. Files updated

- `docs/refactor_workpacks/00_index.md`
- `docs/refactor_workpacks/01_phase_0_contract_lock.md`
- `docs/refactor_workpacks/02_phase_1_identity_and_vocabulary_split.md`
- `docs/refactor_workpacks/03_phase_2_discovery_page_composition_root_extraction.md`
- `docs/refactor_workpacks/04_phase_3_device_registry_split.md`
- `docs/refactor_workpacks/05_phase_3_trusted_lan_peer_store_split.md`
- `docs/refactor_workpacks/06_phase_3_discovery_read_model_cutover.md`
- `docs/refactor_workpacks/07_phase_4_transport_adapter_extraction.md`
- `docs/refactor_workpacks/08_phase_4_packet_codec_split.md`
- `docs/refactor_workpacks/09_phase_4_protocol_handlers_split.md`
- `docs/refactor_workpacks/10_phase_5_shared_cache_metadata_owner.md`
- `docs/refactor_workpacks/11_phase_5_shared_cache_index_store_split.md`
- `docs/refactor_workpacks/12_phase_5_controller_cache_mirror_removal.md`
- `docs/refactor_workpacks/13_phase_6_clipboard_history_extraction.md`
- `docs/refactor_workpacks/14_phase_6_remote_share_browser_extraction.md`
- `docs/refactor_workpacks/15_phase_6_files_feature_state_owner_split.md`
- `docs/refactor_workpacks/16_phase_6_preview_cache_owner_split.md`
- `docs/refactor_workpacks/17_phase_6_transfer_session_coordinator_split.md`
- `docs/refactor_workpacks/18_deletion_wave_map.md`
- `docs/refactor_workpacks/19_test_gates_matrix.md`
- `docs/refactor_workpacks/20_phase_3_discovery_controller_legacy_field_downgrade.md`
- `docs/refactor_workpacks/21_phase_4_protocol_dispatch_facade_removal.md`
- `docs/refactor_workpacks/22_phase_5_shared_cache_read_cutover.md`
- `docs/refactor_workpacks/23_phase_6_obsolete_cross_feature_callbacks_removal.md`

## 3. Missing slices closed

- Added a dedicated Phase 1 workpack for `InternetPeerEndpointStore` activation.
- Added a dedicated Phase 1 workpack for `SettingsStore` activation.
- Added a dedicated Phase 6 workpack for remote clipboard projection and `ClipboardSheet -> DiscoveryController` remote coupling.
- Added a dedicated Phase 6 workpack for discovery-owned download history extraction.
- Expanded `20` so `_friends`, `_loadSettings`, and `_saveSettings` now have owning deletion logic instead of remaining orphaned in the backlog.

## 4. Dependency fixes

- `06` now depends on `03a` and no longer assumes a missing internet-endpoint seam.
- `14` now depends on `06`, `09`, `12`, and `22`, so browse-session extraction starts only after discovery read-side and shared-cache cutovers exist.
- `17` now depends on `21`, and explicitly excludes `VideoLinkShareService.activeSession` instead of silently absorbing it.
- `13b` now depends on `17`, so history extraction no longer races transfer-session ownership cleanup.
- `23` now depends on `06`, `13`, `13a`, `13b`, `14`, `15`, `16`, and `17`, matching real callback/facade deletion prerequisites.
- `00_index.md` dependency graph and parallelism rules were rewritten to match these handoffs.

## 5. Gate fixes

- `19_test_gates_matrix.md` is now canonical and normalized to `GATE-01` through `GATE-07`.
- Every executable workpack now references explicit `GATE-*` IDs in `## 10. Test gate`.
- `04`, `20`, and `22` were synchronized with the matrix where the audit had identified missing gate traceability.
- Protocol-sensitive workpacks now bind to `GATE-02`; shared-cache workpacks bind to `GATE-05`; UI cutovers and deletions bind to `GATE-06` and `GATE-07` where needed.

## 6. Deletion-map fixes

- Added deletion ownership for `_downloadHistory`.
- Added deletion ownership for `_friends` as a legacy controller cluster.
- Added deletion ownership for `_loadSettings` and `_saveSettings`.
- Split `ClipboardSheet -> DiscoveryController` deletion into remote-projection slice (`13a`) plus final full-surface cleanup (`23`).
- Added bridge and facade deletion rows for `PeerVocabularyAdapter`, `DeviceIdentityBridge`, `ProtocolDispatchFacade`, `SharedCacheCatalogBridge`, `TransferSessionBridge`, `LegacyDiscoveryFacade`, and `FileExplorerFacade`.
- Synchronized `00_index.md` deletion waves with `18_deletion_wave_map.md`.

## 7. Remaining explicit uncertainty

- `03_phase_2_discovery_page_composition_root_extraction.md` uses `app-level composition root` as a derived planning helper; the exact injection surface is not code-visible yet.
- `13a_phase_6_remote_clipboard_projection_extraction.md` uses a derived session-scoped remote clipboard projection boundary because the master plan did not name a dedicated owner.
- `13b_phase_6_download_history_extraction.md` uses a derived history boundary because the master plan and current Dart audit confirm the legacy seam but not a concrete target type.
- `17_phase_6_transfer_session_coordinator_split.md` explicitly excludes `VideoLinkShareService.activeSession`; the current Dart-layer audit does not prove it belongs to the same transfer-session seam.
- `21_phase_4_protocol_dispatch_facade_removal.md` keeps an uncertainty block because `ProtocolDispatchFacade` is a planned temporary bridge, not a current code artifact.
- `23_phase_6_obsolete_cross_feature_callbacks_removal.md` keeps an uncertainty block because final callback inventory depends on how temporary facades are instantiated during prior workpacks.

## 8. Final status

`Execution-ready with explicit uncertainty`
