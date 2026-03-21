# Test Gates Matrix

Derived from `docs/refactor_master_plan.md` and the tactical workpacks in `docs/refactor_workpacks/`.

| Gate ID | Test family | Required before workpack | Protects | Hard stop failure | Related compatibility anchor |
| --- | --- | --- | --- | --- | --- |
| GATE-01 | repository contract tests | `01`, `02`, `05`, `10`, `13` | SQLite table semantics and persistence invariants | persisted rows no longer round-trip under pre-migration semantics | `known_devices`, `shared_folder_caches`, `friends`, `app_settings`, `clipboard_history`, `transfer_history` |
| GATE-02 | protocol compatibility tests | `01`, `07`, `08`, `09`, `17`, `21` | packet identifiers and envelope semantics | packet shape or decode semantics drift | `LANDA_DISCOVER_V1`, `LANDA_HERE_V1`, `LANDA_TRANSFER_REQUEST_V1`, `LANDA_CLIPBOARD_CATALOG_V1` |
| GATE-03 | identity mapping tests | `01`, `02`, `04`, `05`, `20` | MAC-vs-IP identity continuity | alias/trust no longer follows same MAC after IP change | `known_devices`, `normalizeMac` |
| GATE-04 | session continuity tests | `09`, `17`, `21` | inbound/outbound transfer session continuity | accepted session cannot complete end-to-end | transfer request/decision semantics |
| GATE-05 | shared cache consistency tests | `10`, `11`, `12`, `14`, `22` | metadata/index consistency and receiver cache stability | DB rows and JSON index diverge | `shared_folder_caches`, JSON index files |
| GATE-06 | UI integration smoke tests | `03`, `06`, `12`, `13`, `14`, `15`, `16`, `23` | screen and feature flow survivability during cutovers | page or sheet cannot open/use target flow | `DiscoveryPage`, `ClipboardSheet`, files feature entry flows |
| GATE-07 | migration regression tests | `04`, `06`, `12`, `13`, `15`, `16`, `23` | parity between legacy and target read paths during temporary cutovers | old and new paths diverge before deletion proof | legacy mirrors, facades, temporary bridges |
