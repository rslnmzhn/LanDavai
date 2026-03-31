# Test Gates Matrix

Derived from `docs/refactor_master_plan.md` and `docs/refactor_workpacks/00_index.md`.

| Gate ID | Test family | Required before workpack | Protects | Current concrete tests |
| --- | --- | --- | --- | --- |
| `GATE-01` | local identity and persistence contract tests | `01` | `local_peer_id` semantics and isolation from friend endpoint ownership | `test/local_peer_identity_store_test.dart`, `test/discovery_controller_settings_store_test.dart`, `test/settings_store_test.dart` |
| `GATE-02` | shared-cache maintenance and catalog/index integration tests | `04`, `05`, `07` | shared-cache maintenance commands, progress, metadata/index consistency | `test/shared_cache_catalog_test.dart`, `test/shared_cache_index_store_test.dart`, `test/shared_cache_maintenance_boundary_test.dart` |
| `GATE-03` | discovery/files UI smoke and widget tests | `02`, `03`, `04`, `05` | discovery entry flows, files entry flows, history/clipboard launch survivability after UI shell changes | `test/smoke_test.dart`, `test/blocked_entry_flow_regression_test.dart`, `test/files_presentation_import_test.dart` |
| `GATE-04` | remote-share media and thumbnail regression tests | `06`, `07` | thumbnail reuse, projection update, preview/thumbnail path continuity | `test/remote_share_media_projection_boundary_test.dart`, `test/remote_share_browser_test.dart`, `test/preview_cache_owner_test.dart` |
| `GATE-05` | transfer and video-link continuity tests | `08` | separation between file-transfer session truth and watch-link session truth | `test/transfer_session_coordinator_test.dart`, `test/video_link_session_boundary_test.dart`, `test/video_link_share_service_test.dart` |
| `GATE-06` | protocol compatibility tests | `09` | packet identifiers, envelope semantics, and codec parity during module split | `test/lan_packet_codec_test.dart`, `test/lan_discovery_service_contract_test.dart`, `test/lan_discovery_service_packet_codec_test.dart`, `test/lan_discovery_service_protocol_handlers_test.dart`, `test/lan_discovery_service_transport_adapter_test.dart` |
| `GATE-07` | architecture guard tests | `04`, `05`, `10` | no reintroduction of temporary bridges, callback backchannels, or critical `part` ownership | `test/architecture_guard_test.dart` |
| `GATE-08` | full regression suite | `01` through `10` | overall app continuity after every structural change | `flutter analyze`, `flutter test` |
