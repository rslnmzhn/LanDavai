# Test Gates Matrix

Derived from `docs/refactor_master_plan.md` and `docs/refactor_workpacks/00_index.md`.

| Gate ID | Test family | Required before workpack | Protects | Hard stop failure |
| --- | --- | --- | --- | --- |
| `GATE-01` | local identity and persistence contract tests | `01` | `local_peer_id` semantics and isolation from friend endpoint ownership | local peer identity still round-trips only through `FriendRepository` or silently drifts |
| `GATE-02` | shared-cache maintenance and catalog/index integration tests | `04`, `05`, `07` | shared-cache maintenance commands, progress, metadata/index consistency | shared-cache maintenance path or metadata/index parity drifts |
| `GATE-03` | discovery/files UI smoke and widget tests | `02`, `03`, `04`, `05` | discovery entry flows, files entry flows, history/clipboard launch survivability after UI shell changes | a key screen or modal can no longer open or render correctly |
| `GATE-04` | remote-share media and thumbnail regression tests | `06`, `07` | thumbnail reuse, projection update, preview/thumbnail path continuity | remote-share media updates require controller/repository bypass to work |
| `GATE-05` | transfer and video-link continuity tests | `08` | separation between file-transfer session truth and watch-link session truth | transfer and video-link flows interfere or one breaks during separation |
| `GATE-06` | protocol compatibility tests | `09` | packet identifiers, envelope semantics, and codec parity during module split | wire semantics drift or decode parity breaks |
| `GATE-07` | architecture guard tests | `04`, `05`, `10` | no reintroduction of temporary bridges, callback backchannels, or critical `part` ownership | prohibited architectural residue can be added without a failing test |
| `GATE-08` | full regression suite | `01` through `10` | overall app continuity after every structural change | `flutter analyze` or `flutter test` fails |
