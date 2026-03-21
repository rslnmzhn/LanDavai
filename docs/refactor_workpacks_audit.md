# Refactor Workpacks Audit

## 1. Overall verdict

Decomposition is partially broken. It is close enough to salvage, but not honest enough to execute as-is one workpack at a time.

Главный риск не в количестве файлов. Главный риск в том, что tactical backlog потерял несколько обязательных seams из `docs/refactor_master_plan.md`, а почти все executable workpacks потеряли явные ownership guards:
- нет явного поля `Forbidden writers`
- нет явного поля `Forbidden dual-write paths`
- часть read-model и session workpacks опирается на target owners, для которых нет собственного workpack
- test-gate traceability between `00_index.md`, `19_test_gates_matrix.md` and the workpacks is incomplete

Итог: работать по одному workpack формально можно, но реально нельзя доверять sequencing и completion proof без правок. Набор пока не execution-ready.

## 2. Coverage map

| Master plan slice | Covered by workpack(s) | Coverage status | Notes |
| --- | --- | --- | --- |
| Phase 0 contract lock | `01`, `19` | Covered | Good baseline split. |
| Vocabulary reset | `02` | Partial | Covered only together with local identity split; no separate treatment for endpoint/store boundary. |
| `LocalPeerIdentityStore` activation | `02` | Covered | Narrow enough, but tied to broader vocabulary workpack. |
| `InternetPeerEndpointStore` activation | None | Missing | Present in master plan target ownership model, absent from workpacks. |
| `SettingsStore` activation | None | Missing | Present in master plan target ownership model, absent from workpacks. |
| Phase 2 composition root extraction | `03` | Covered | Scope is narrow and aligned. |
| `DeviceRegistry` split | `04` | Covered | Good seam coverage. |
| `TrustedLanPeerStore` split | `05` | Covered | Good seam coverage. |
| Discovery read/application model cutover | `06` | Partial | Declared, but depends on absent `InternetPeerEndpointStore` slice. |
| DiscoveryController legacy identity/trust field downgrade | `20` | Covered | Added correctly as extra tactical slice. |
| Transport lifecycle extraction | `07` | Covered | Narrow seam. |
| Packet codec split | `08` | Covered | Narrow seam. |
| Per-scenario protocol handlers split | `09` | Partial | Covered, but too broad for one executable slice. |
| Protocol dispatch facade removal | `21` | Covered | Necessary extra slice. |
| Shared cache metadata ownership | `10` | Covered | Good seam. |
| Shared cache index ownership | `11` | Covered | Good seam. |
| Shared cache read cutover | `22` | Covered | Necessary extra slice. |
| Controller cache mirror elimination | `12` | Covered | Good deletion-focused slice. |
| Clipboard local history extraction | `13` | Partial | Local history only. Remote clipboard projection remains unplanned. |
| Remote clipboard session/projection extraction | None | Missing | Master plan identifies remote clipboard runtime state in discovery; no workpack owns this cutover. |
| Remote share browser extraction | `14` | Covered | Good seam, but missing dependency. |
| Files feature state owner split | `15` | Covered | Good seam. |
| Preview cache owner split | `16` | Covered | Good seam. |
| Transfer session coordinator split | `17` | Partial | Covered, but too broad and architecturally ambiguous around video-link session evidence. |
| History/download history extraction from discovery-owned state | None | Missing | Master plan names `history` in Phase 6 and `_downloadHistory` in discovery state; no workpack owns it. |
| Obsolete cross-feature callback removal | `23` | Covered | Covered, but broad cleanup cluster. |
| Deletion-wave coordination | `18` | Partial | Useful map, but incomplete artifact coverage. |
| Test-gate coordination | `19` | Partial | Useful map, but mismatched against declared workpack gates. |

## 3. Index quality verdict

Registry quality:
- Good as a control surface.
- Broken as a truthful registry because it omits required slices for `InternetPeerEndpointStore`, `SettingsStore`, remote clipboard projection, and discovery-owned history/download history.
- `Required test gate` is written as free text, not normalized to `GATE-*`, which weakens execution traceability.

Dependency graph quality:
- No explicit cycle detected.
- Hidden missing dependencies exist.
- `06` assumes read-side dependencies from master plan that no workpack activates.
- `14` should depend on `06`, not only on Phase 4/5 cache work.
- `17` should at least justify why `21` is not required; today it does not.
- `23` should depend explicitly on `06` because it deletes `LegacyDiscoveryFacade`.

Parallelism rules quality:
- Mostly coherent.
- Still unsafe because they are built on an incomplete graph.
- Parallelism claims around later Phase 6 workpacks are optimistic while callback and remote clipboard gaps remain unresolved.

Deletion wave logic quality:
- The wave model is useful.
- It is incomplete because it does not cover `_downloadHistory`, `_friends`, `_loadSettings`, `_saveSettings`, or the direct `ClipboardSheet -> DiscoveryController` dependency beyond local history.

## 4. Workpack-by-workpack audit

### Workpack 00
- `Verdict`: Partial
- `Too broad?`: No
- `Missing dependency?`: N/A
- `Ownership model complete?`: N/A for index, but registry does not expose missing owners from master plan
- `Cutover logic complete?`: N/A
- `Bridge discipline complete?`: Partial; bridge rows exist, but registry hides missing ownership slices
- `Deletion logic complete?`: Partial
- `Test gate complete?`: Partial; free-text gates instead of `GATE-*`
- `Evidence discipline honest?`: Mixed; no explicit evidence label
- `Compatibility anchors preserved?`: Partial
- `Key defects`: missing slices in registry; hidden dependency gaps; weak gate traceability
- `Required fix`: add missing slices to registry or mark them explicitly missing; normalize gates to `GATE-*`

### Workpack 01
- `Verdict`: Executable after template fix
- `Too broad?`: No
- `Missing dependency?`: No
- `Ownership model complete?`: Partial; no explicit `Forbidden writers`
- `Cutover logic complete?`: Yes for a no-cutover baseline workpack
- `Bridge discipline complete?`: Yes
- `Deletion logic complete?`: Yes
- `Test gate complete?`: Yes
- `Evidence discipline honest?`: Yes
- `Compatibility anchors preserved?`: Yes
- `Key defects`: systemic template omission of `Forbidden writers` / explicit forbidden dual-write declaration
- `Required fix`: state explicitly that no new writer may appear before later workpacks

### Workpack 02
- `Verdict`: Broken
- `Too broad?`: Yes
- `Missing dependency?`: Not as graph syntax, but it hides missing slices for `InternetPeerEndpointStore` and `SettingsStore`
- `Ownership model complete?`: No; target owner is only `LocalPeerIdentityStore`, while master plan requires more ownership splits in Phase 1
- `Cutover logic complete?`: Partial; cutover is specified only for local peer identity
- `Bridge discipline complete?`: Yes
- `Deletion logic complete?`: Partial
- `Test gate complete?`: Partial
- `Evidence discipline honest?`: Mixed
- `Compatibility anchors preserved?`: Partial; `friends` and `app_settings` are covered, but the full friend/endpoint/settings split is not
- `Key defects`: one workpack tries to absorb vocabulary reset plus identity split, but leaves `InternetPeerEndpointStore` and `SettingsStore` without owning workpacks
- `Required fix`: split or amend into separate tactical slices for local identity, internet endpoint ownership, and settings ownership

### Workpack 03
- `Verdict`: Executable after template fix
- `Too broad?`: No
- `Missing dependency?`: No
- `Ownership model complete?`: Partial; no explicit `Forbidden writers`
- `Cutover logic complete?`: Yes
- `Bridge discipline complete?`: Yes
- `Deletion logic complete?`: Yes
- `Test gate complete?`: Yes
- `Evidence discipline honest?`: Mixed; `app-level composition root` is a planning helper, not a code-confirmed artifact
- `Compatibility anchors preserved?`: Yes
- `Key defects`: evidence label overclaims if read as proof of target structure
- `Required fix`: split evidence between current code problem and planned target boundary

### Workpack 04
- `Verdict`: Executable after template fix
- `Too broad?`: No
- `Missing dependency?`: No
- `Ownership model complete?`: Partial; missing explicit `Forbidden writers`
- `Cutover logic complete?`: Yes
- `Bridge discipline complete?`: Yes
- `Deletion logic complete?`: Yes
- `Test gate complete?`: Partial; `19` does not list `04` under repository contract tests
- `Evidence discipline honest?`: Mixed; the problem is confirmed, `DeviceRegistry` is planned
- `Compatibility anchors preserved?`: Yes
- `Key defects`: missing forbidden writers; gate matrix mismatch
- `Required fix`: add explicit forbidden writers and sync `19` with `04`

### Workpack 05
- `Verdict`: Executable after template fix
- `Too broad?`: No
- `Missing dependency?`: No
- `Ownership model complete?`: Partial; missing explicit `Forbidden writers`
- `Cutover logic complete?`: Yes
- `Bridge discipline complete?`: Yes
- `Deletion logic complete?`: Yes
- `Test gate complete?`: Yes
- `Evidence discipline honest?`: Mixed
- `Compatibility anchors preserved?`: Yes
- `Key defects`: missing forbidden writers; explicit forbidden dual-write path is only implied, not captured as a dedicated field
- `Required fix`: add explicit forbidden writers and forbidden dual-write paths field

### Workpack 06
- `Verdict`: Risky
- `Too broad?`: Borderline, but acceptable if dependencies were complete
- `Missing dependency?`: Yes
- `Ownership model complete?`: Partial; missing explicit forbidden writers
- `Cutover logic complete?`: Partial; target read/write path assumes explicit owners that are not all activated
- `Bridge discipline complete?`: Yes
- `Deletion logic complete?`: Partial
- `Test gate complete?`: Yes
- `Evidence discipline honest?`: Mixed
- `Compatibility anchors preserved?`: Partial; no explicit anchor discussion even though it redirects user intents
- `Key defects`: depends implicitly on `InternetPeerEndpointStore`, which has no workpack
- `Required fix`: add the missing ownership slice or mark `06` explicitly blocked by missing Phase 1 endpoint work

### Workpack 07
- `Verdict`: Executable after template fix
- `Too broad?`: No
- `Missing dependency?`: No
- `Ownership model complete?`: Partial; missing explicit forbidden writers
- `Cutover logic complete?`: Yes
- `Bridge discipline complete?`: Yes
- `Deletion logic complete?`: Yes
- `Test gate complete?`: Yes
- `Evidence discipline honest?`: Acceptable
- `Compatibility anchors preserved?`: Partial; touches UDP semantics but does not restate handshake identifiers explicitly
- `Key defects`: compatibility anchors are only indirectly referenced
- `Required fix`: explicitly name the transport-side packet/handshake anchors in this workpack

### Workpack 08
- `Verdict`: Executable after template fix
- `Too broad?`: No
- `Missing dependency?`: No
- `Ownership model complete?`: Partial; missing explicit forbidden writers
- `Cutover logic complete?`: Yes
- `Bridge discipline complete?`: Yes
- `Deletion logic complete?`: Yes
- `Test gate complete?`: Yes
- `Evidence discipline honest?`: Acceptable
- `Compatibility anchors preserved?`: Mostly yes
- `Key defects`: no explicit forbidden writers; anchor list could be more concrete
- `Required fix`: add forbidden writers and list exact packet families covered

### Workpack 09
- `Verdict`: Risky
- `Too broad?`: Yes
- `Missing dependency?`: No hard missing dependency, but it stretches one workpack across multiple handler families
- `Ownership model complete?`: Partial; missing explicit forbidden writers
- `Cutover logic complete?`: Partial; “scenario handlers by scenario” is still too coarse
- `Bridge discipline complete?`: Yes
- `Deletion logic complete?`: Partial
- `Test gate complete?`: Yes
- `Evidence discipline honest?`: Mixed
- `Compatibility anchors preserved?`: Partial; packet families are not explicitly anchored
- `Key defects`: it mixes discovery/friend/share/clipboard/transfer handler splits into one mini-master-plan
- `Required fix`: split by handler families or at least state explicit sub-slices and cutover order inside the workpack

### Workpack 10
- `Verdict`: Executable after template fix
- `Too broad?`: No
- `Missing dependency?`: No
- `Ownership model complete?`: Partial; missing explicit forbidden writers
- `Cutover logic complete?`: Yes
- `Bridge discipline complete?`: Yes
- `Deletion logic complete?`: Yes
- `Test gate complete?`: Yes
- `Evidence discipline honest?`: Acceptable
- `Compatibility anchors preserved?`: Yes
- `Key defects`: no explicit forbidden writers
- `Required fix`: add forbidden writers and explicit forbidden bypass paths through repository/controller

### Workpack 11
- `Verdict`: Executable after template fix
- `Too broad?`: No
- `Missing dependency?`: No
- `Ownership model complete?`: Partial; missing explicit forbidden writers
- `Cutover logic complete?`: Yes
- `Bridge discipline complete?`: Yes
- `Deletion logic complete?`: Yes
- `Test gate complete?`: Yes
- `Evidence discipline honest?`: Acceptable
- `Compatibility anchors preserved?`: Partial; JSON index anchor is explicit, table anchor is only implicit
- `Key defects`: ownership guard fields absent
- `Required fix`: add forbidden writers and explicit statement that JSON index is the only moved artifact in this slice

### Workpack 12
- `Verdict`: Executable after template fix
- `Too broad?`: No
- `Missing dependency?`: No
- `Ownership model complete?`: Partial; missing explicit forbidden writers
- `Cutover logic complete?`: Yes
- `Bridge discipline complete?`: Yes
- `Deletion logic complete?`: Yes
- `Test gate complete?`: Yes
- `Evidence discipline honest?`: Acceptable
- `Compatibility anchors preserved?`: Partial; shared cache anchors are implied, not restated
- `Key defects`: relies on `22`, but does not restate the anchor risk of deleting mirrors too early
- `Required fix`: make compatibility anchors explicit and add forbidden writers

### Workpack 13
- `Verdict`: Partial
- `Too broad?`: No
- `Missing dependency?`: Yes, at backlog level
- `Ownership model complete?`: Partial; missing explicit forbidden writers
- `Cutover logic complete?`: Partial; it only covers local durable history
- `Bridge discipline complete?`: Yes
- `Deletion logic complete?`: Partial
- `Test gate complete?`: Yes
- `Evidence discipline honest?`: Acceptable
- `Compatibility anchors preserved?`: Yes for `clipboard_history`
- `Key defects`: `ClipboardSheet` still has unresolved controller dependency for remote clipboard projection; the title overstates the actual cutover
- `Required fix`: either narrow the title/scope explicitly to local history only everywhere or add the missing remote clipboard slice

### Workpack 14
- `Verdict`: Risky
- `Too broad?`: No
- `Missing dependency?`: Yes
- `Ownership model complete?`: Partial; missing explicit forbidden writers
- `Cutover logic complete?`: Mostly yes
- `Bridge discipline complete?`: Yes
- `Deletion logic complete?`: Yes
- `Test gate complete?`: Yes
- `Evidence discipline honest?`: Acceptable
- `Compatibility anchors preserved?`: Partial; it touches receiver cache and share-catalog flow without explicitly restating those anchors
- `Key defects`: should depend on `06`; currently it assumes discovery-side read cutover context exists
- `Required fix`: add explicit dependency on `06` and name the shared-cache and share-catalog anchors directly

### Workpack 15
- `Verdict`: Executable after template fix
- `Too broad?`: No
- `Missing dependency?`: No hard missing dependency
- `Ownership model complete?`: Partial; missing explicit forbidden writers
- `Cutover logic complete?`: Yes
- `Bridge discipline complete?`: Yes
- `Deletion logic complete?`: Yes
- `Test gate complete?`: Yes
- `Evidence discipline honest?`: Acceptable
- `Compatibility anchors preserved?`: Mostly yes; this slice is UI-state-heavy
- `Key defects`: relies on `FileExplorerFacade` but still lacks explicit forbidden writer field
- `Required fix`: add forbidden writers and explicit statement that shared cache metadata writes remain forbidden here

### Workpack 16
- `Verdict`: Executable after template fix
- `Too broad?`: No
- `Missing dependency?`: No
- `Ownership model complete?`: Partial; missing explicit forbidden writers
- `Cutover logic complete?`: Yes
- `Bridge discipline complete?`: Yes
- `Deletion logic complete?`: Yes
- `Test gate complete?`: Yes
- `Evidence discipline honest?`: Acceptable
- `Compatibility anchors preserved?`: Acceptable
- `Key defects`: ownership guard fields absent
- `Required fix`: add forbidden writers and explicit forbidden file-write bypass path

### Workpack 17
- `Verdict`: Risky
- `Too broad?`: Yes
- `Missing dependency?`: Yes
- `Ownership model complete?`: Partial; missing explicit forbidden writers
- `Cutover logic complete?`: Partial; the session boundary is underspecified
- `Bridge discipline complete?`: Yes
- `Deletion logic complete?`: Partial
- `Test gate complete?`: Yes
- `Evidence discipline honest?`: Mixed; it uses `VideoLinkShareService.activeSession` as evidence while the master plan treats video-share decomposition as secondary
- `Compatibility anchors preserved?`: Partial; `transfer_history` and transfer packet anchors are not fully named
- `Key defects`: it tries to consolidate all transfer/session truth in one slice without clarifying whether video-link session is in scope or explicitly excluded; it also should justify why `21` is not a dependency
- `Required fix`: narrow scope or split it; explicitly define whether video-link session is out of scope and add the missing dependency or rationale

### Workpack 18
- `Verdict`: Partial
- `Too broad?`: N/A, support doc
- `Missing dependency?`: N/A
- `Ownership model complete?`: N/A
- `Cutover logic complete?`: N/A
- `Bridge discipline complete?`: Partial
- `Deletion logic complete?`: No
- `Test gate complete?`: Partial
- `Evidence discipline honest?`: Acceptable
- `Compatibility anchors preserved?`: Partial
- `Key defects`: deletion map omits meaningful artifacts from master plan: `_downloadHistory`, `_friends`, `_loadSettings`, `_saveSettings`, unresolved `ClipboardSheet -> DiscoveryController` dependency
- `Required fix`: add the missing artifacts or mark their owning slices missing

### Workpack 19
- `Verdict`: Partial
- `Too broad?`: N/A, support doc
- `Missing dependency?`: N/A
- `Ownership model complete?`: N/A
- `Cutover logic complete?`: N/A
- `Bridge discipline complete?`: N/A
- `Deletion logic complete?`: N/A
- `Test gate complete?`: No
- `Evidence discipline honest?`: Acceptable
- `Compatibility anchors preserved?`: Mostly yes
- `Key defects`: matrix does not fully match workpack preconditions; `04` is missing under repository contracts, `20` is missing under UI smoke, `22` is missing under UI smoke
- `Required fix`: make `19` the canonical source and sync all rows with actual workpack “До начала нужны”

### Workpack 20
- `Verdict`: Executable after template fix
- `Too broad?`: No
- `Missing dependency?`: No
- `Ownership model complete?`: Partial; missing explicit forbidden writers
- `Cutover logic complete?`: Yes
- `Bridge discipline complete?`: Yes
- `Deletion logic complete?`: Yes
- `Test gate complete?`: Partial; `19` misses its UI smoke precondition
- `Evidence discipline honest?`: Acceptable
- `Compatibility anchors preserved?`: Partial; `known_devices` anchor is implied rather than stated
- `Key defects`: gate matrix mismatch; ownership guard fields absent
- `Required fix`: sync `19` and add explicit forbidden writers

### Workpack 21
- `Verdict`: Executable after template fix
- `Too broad?`: No
- `Missing dependency?`: No
- `Ownership model complete?`: Partial; missing explicit forbidden writers
- `Cutover logic complete?`: Yes
- `Bridge discipline complete?`: Yes
- `Deletion logic complete?`: Yes
- `Test gate complete?`: Yes
- `Evidence discipline honest?`: Mixed; problem is inferred correctly, but there is no code-visible `ProtocolDispatchFacade`
- `Compatibility anchors preserved?`: Partial; it should restate packet anchor set more explicitly
- `Key defects`: evidence label and source anchor do not clearly distinguish “current code problem” from “temporary bridge invented by plan”
- `Required fix`: clarify evidence boundary and add explicit compatibility anchors

### Workpack 22
- `Verdict`: Partial
- `Too broad?`: No
- `Missing dependency?`: No
- `Ownership model complete?`: Partial; missing explicit forbidden writers
- `Cutover logic complete?`: Yes
- `Bridge discipline complete?`: Yes
- `Deletion logic complete?`: Yes
- `Test gate complete?`: Partial; `19` misses its UI smoke precondition
- `Evidence discipline honest?`: Acceptable
- `Compatibility anchors preserved?`: Yes
- `Key defects`: gate matrix mismatch; explicit forbidden writers absent
- `Required fix`: sync `19` and add ownership guard field

### Workpack 23
- `Verdict`: Risky
- `Too broad?`: Yes
- `Missing dependency?`: Yes
- `Ownership model complete?`: Partial; missing explicit forbidden writers
- `Cutover logic complete?`: Partial; it is a cleanup cluster, not one narrow seam
- `Bridge discipline complete?`: Yes
- `Deletion logic complete?`: Partial
- `Test gate complete?`: Yes
- `Evidence discipline honest?`: Mixed
- `Compatibility anchors preserved?`: Partial
- `Key defects`: bundles `LegacyDiscoveryFacade` removal, `FileExplorerFacade` removal, and callback mesh removal across multiple features; should depend explicitly on `06`
- `Required fix`: split or at least stage its internal order and add the missing dependency on `06`

## 5. Cross-workpack defects

1. Missing Phase 1 ownership handoff:
   - `InternetPeerEndpointStore` exists in `docs/refactor_master_plan.md` but has no tactical workpack.
   - `SettingsStore` exists in `docs/refactor_master_plan.md` but has no tactical workpack.
   - This breaks Phase 1 coverage and leaves later read-model workpacks with hidden dependencies.

2. Missing clipboard seam:
   - `13` extracts only local history.
   - `ClipboardSheet.remoteClipboardEntriesFor` is called out in master plan evidence, but there is no workpack that rehomes remote clipboard session/projection.
   - Result: `ClipboardSheet -> DiscoveryController` coupling is not actually closed.

3. Missing history seam:
   - master plan explicitly names Phase 6 as `clipboard, history, and files extraction from discovery-owned state`.
   - `_downloadHistory` appears in `DiscoveryController` evidence in the master plan.
   - No workpack owns that seam, so Phase 6 coverage is incomplete.

4. Dependency mismatch:
   - `06` assumes read access to target owners that have no workpack activation.
   - `14` should depend on `06`.
   - `17` should either depend on `21` or explicitly justify why facade removal is not required before session consolidation.
   - `23` should depend on `06` because it deletes `LegacyDiscoveryFacade`.

5. Systemic ownership-template defect:
   - Executable workpacks carry `Single write authority after cutover`.
   - None carry explicit `Forbidden writers`.
   - None carry an explicit `Forbidden dual-write paths` field.
   - This means the set preserves the idea of single-writer model, but not the enforcement surface.

6. Systemic honesty defect:
   - `docs/refactor_workpacks/` contains zero occurrences of `Missing artifact`, `Impact of uncertainty`, `Safest interim assumption`.
   - Several workpacks clearly needed them, especially `02`, `06`, `17`, `21`, `23`.

7. Gate traceability mismatch:
   - `19_test_gates_matrix.md` is not the canonical mirror of workpack preconditions.
   - At minimum, it misses `04 -> repository contract tests`, `20 -> UI smoke tests`, `22 -> UI smoke tests`.

8. Deletion traceability gap:
   - `18_deletion_wave_map.md` and `00_index.md` do not own or track deletion of `_downloadHistory`, `_friends`, `_loadSettings`, `_saveSettings`, or the unresolved clipboard controller dependency.

## 6. Split recommendations

| Current workpack | Why it is too broad | Recommended split | Why the split improves execution |
| --- | --- | --- | --- |
| `02_phase_1_identity_and_vocabulary_split.md` | It mixes vocabulary reset, local peer identity separation, and implicitly absorbs missing endpoint/settings seams without actually owning them | 1. local peer identity cutover 2. internet peer endpoint ownership activation 3. settings ownership boundary cleanup | Restores one major seam per workpack and closes missing Phase 1 coverage |
| `09_phase_4_protocol_handlers_split.md` | It spans discovery, friend, share, clipboard, and transfer handlers in one package | 1. presence/friend handlers 2. share/clipboard handlers 3. transfer negotiation handlers | Cuts protocol split by scenario family and reduces blast radius per migration slice |
| `17_phase_6_transfer_session_coordinator_split.md` | It tries to consolidate all transfer/session truth, while evidence drifts into `VideoLinkShareService.activeSession` ambiguity | 1. transfer negotiation/session authority 2. file-transfer execution handoff 3. explicit video-link exclusion or separate secondary workpack | Prevents a new vague mega-coordinator and removes the current scope ambiguity |
| `23_phase_6_obsolete_cross_feature_callbacks_removal.md` | It bundles callback mesh removal plus multiple facade deletions across features | 1. `LegacyDiscoveryFacade` removal 2. files/callback backchannel removal 3. final cross-feature callback cleanup proof | Makes deletion wave executable and reduces the chance of deleting too much at once |

## 7. Must-fix list before execution

Blockers:
- Add missing tactical coverage for `InternetPeerEndpointStore`.
- Add missing tactical coverage for `SettingsStore`.
- Add missing tactical coverage for remote clipboard projection/session ownership.
- Add missing tactical coverage for discovery-owned history/download history extraction.
- Add explicit `Forbidden writers` and explicit `Forbidden dual-write paths` fields to every executable workpack.

Major defects:
- Fix dependency graph: `06`, `14`, `17`, `23`.
- Sync `19_test_gates_matrix.md` with actual pre-start gates.
- Expand `18_deletion_wave_map.md` to cover all legacy artifacts named in the master plan.
- Narrow or split `02`, `09`, `17`, `23`.

Medium defects:
- Make evidence labels honest by separating current-code evidence from planned target assertions.
- Normalize `00_index.md` gate references to `GATE-*`.
- Make compatibility anchors explicit in protocol-sensitive workpacks `07`, `09`, `14`, `17`, `21`.

## 8. Final verdict

Not execution-ready.

Причина не в том, что workpacks “плохие вообще”. Причина в том, что набор пока не замыкает все обязательные ownership seams из `docs/refactor_master_plan.md`, а формальные гарантии single-writer discipline внутри workpacks ослаблены.

Если исправить blockers и major defects, набор станет рабочим tactical backlog. Без этих правок это не backlog для пошагового исполнения, а черновик backlog-а.
