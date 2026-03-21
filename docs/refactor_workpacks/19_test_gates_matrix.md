# Test Gates Matrix

Derived from `docs/refactor_master_plan.md` and the tactical workpacks in `docs/refactor_workpacks/`.

| Gate ID | Test family | Required before workpack | Protects | Hard stop failure | Related compatibility anchor |
| --- | --- | --- | --- | --- | --- |
| GATE-01 | repository contract tests | `02`, `03a`, `03b`, `04`, `05`, `10`, `13`, `20` | SQLite table semantics and persistence invariants | persisted rows no longer round-trip under pre-migration semantics | `known_devices`, `shared_folder_caches`, `friends`, `app_settings`, `clipboard_history`, `transfer_history` |
| GATE-02 | protocol compatibility tests | `07`, `08`, `09`, `13a`, `14`, `17`, `21` | packet identifiers and envelope semantics | packet shape or decode semantics drift | UDP packet envelope semantics, handshake identifiers visible from Dart |
| GATE-03 | identity mapping tests | `02`, `04`, `05`, `20` | MAC-vs-IP identity continuity | alias or trust no longer follows the same MAC after IP change | `known_devices`, `normalizeMac` |
| GATE-04 | session continuity tests | `09`, `17`, `21` | inbound and outbound transfer session continuity | accepted transfer cannot complete end-to-end | transfer request and decision packet families, transfer-session lifecycle |
| GATE-05 | shared cache consistency tests | `10`, `11`, `12`, `14`, `22` | metadata and index alignment plus receiver-cache stability | DB rows and JSON index diverge | `shared_folder_caches`, shared cache JSON index files |
| GATE-06 | UI integration smoke tests | `03`, `06`, `12`, `13`, `13a`, `13b`, `14`, `15`, `16`, `20`, `22`, `23` | screen, sheet, and feature-flow survivability during cutovers | page, sheet, or feature flow cannot open or use the target boundary | `DiscoveryPage`, `ClipboardSheet`, files feature entry flows, history sheet entry flow |
| GATE-07 | migration regression tests | `03a`, `04`, `06`, `12`, `13`, `13a`, `13b`, `14`, `15`, `16`, `17`, `20`, `22`, `23` | parity between legacy and target paths during temporary cutovers | old and new paths diverge before deletion proof | legacy mirrors, temporary bridges, temporary facades |
