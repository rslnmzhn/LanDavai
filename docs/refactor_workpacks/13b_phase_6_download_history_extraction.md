# Workpack: Phase 6 Download History Extraction

## 1. Scope

- Вынести download history runtime ownership from `DiscoveryController._downloadHistory` into an explicit history boundary.
- Отделить history/read-model concerns from live transfer session ownership.
- Не входит: transfer session orchestration itself; это закрывает `17`.

## 2. Source linkage

- `Master phase`: Phase 6
- `Depends on`: `06`, `17`
- `Unblocks`: `23`, `18`
- `Related workpacks`: `17`

## 3. Problem slice

Master plan называет `_downloadHistory` частью discovery-owned state, а Phase 6 explicitly includes history extraction. Этот slice выделен отдельно, потому что download history не должен оставаться побочным mirror inside discovery controller after transfer session ownership is cleaned up.

## 4. Legacy owner and target owner

- `Legacy owner`: `DiscoveryController`
- `Target owner`: download history boundary
- `State seam closed`: history/read-model state separate from live transfer session ownership
- `Single write authority after cutover`: download history boundary
- `Forbidden writers`: `DiscoveryController`, transfer widgets, transfer services writing history read models directly, any callback mutating `_downloadHistory` outside the target boundary
- `Forbidden dual-write paths`: `_downloadHistory` mirror in parallel with explicit history boundary; session-completion flow mutating both coordinator projection and controller history mirror

`download history boundary`:
- `Derived planning helper, not a new architecture component`

## 5. Source of truth impact

- что сейчас является truth:
  - `DiscoveryController._downloadHistory` as discovery-owned runtime history cluster
- что станет truth:
  - download history boundary owning history projection and history-facing mutations only
- что станет projection:
  - history screen lists and download-history view models
- что станет cache:
  - none identified from current Dart-layer audit
- что станет temporary bridge only:
  - `LegacyDiscoveryFacade`

## 6. Read/write cutover

- `Legacy read path`: history-facing UI and related flows read `DiscoveryController._downloadHistory`
- `Target read path`: history-facing UI reads the download history boundary
- `Read switch point`: no history consumer reads `_downloadHistory` as primary truth
- `Legacy write path`: transfer completion or discovery-owned flows append to `_downloadHistory`
- `Target write path`: history updates route to the download history boundary only
- `Write switch point`: no transfer-completion path mutates `_downloadHistory` directly
- `Dual-read allowed?`: yes, during parity checks only
- `Dual-write allowed?`: no

## 7. Temporary bridge

- `Bridge name`: `LegacyDiscoveryFacade`
- `Why it exists`: preserve screen-level wiring while history UI and producers stop reading and writing discovery-owned history state
- `Phase introduced`: Phase 3
- `Max allowed lifetime`: through Phase 6 only
- `Deletion phase`: `23_phase_6_obsolete_cross_feature_callbacks_removal.md`
- `Forbidden long-term use`: cannot preserve history ownership inside discovery controller

## 8. Concrete migration steps

1. inventory every read and write path touching `_downloadHistory`
2. define history boundary separate from transfer session coordinator
3. reroute history reads to the new boundary
4. reroute completion and update writes away from `DiscoveryController`
5. keep only temporary parity checks during cutover
6. run `GATE-06` and `GATE-07`
7. capture proof that `_downloadHistory` can be deleted from discovery-owned state

## 9. Evidence and source anchors

- `Evidence level`: Confirmed from code
- `Source of truth`:
  - `docs/refactor_master_plan.md`
  - `lib/features/discovery/application/discovery_controller.dart` / `_downloadHistory`
  - `lib/features/discovery/presentation/discovery_page.dart` / `_openHistorySheet`
  - `lib/features/transfer/data/file_transfer_service.dart` / `sendFiles`, `startReceiver`
- `Compatibility anchors`:
  - `transfer_history` remains the durable compatibility anchor and must not be repurposed silently
- `Missing artifact`:
  - the current Dart-layer audit does not expose a dedicated history owner in code or in the master plan target-owner list
- `Impact of uncertainty`:
  - the exact implementation shape of the history boundary may vary, but the ownership split cannot be skipped
- `Safest interim assumption`:
  - treat download history as a dedicated read-model boundary separate from `TransferSessionCoordinator` and separate from `DiscoveryController`

## 10. Test gate

- `До начала нужны`: `GATE-06`, `GATE-07`
- `Подтверждают cutover`: history screen and related flows still work without `DiscoveryController._downloadHistory`
- `Hard stop failure`: any history-facing flow still appends to or reads from `_downloadHistory` after cutover

## 11. Completion criteria

- discovery controller no longer owns download history state
- history-facing UI reads from the dedicated boundary only
- this seam stays separate from live transfer session ownership in `17`

## 12. Deletions unlocked

- `DiscoveryController._downloadHistory`
- contributes to final `LegacyDiscoveryFacade` deletion in `23`

## 13. Anti-regression notes

- запрещено скрывать `_downloadHistory` behind a renamed helper or facade
- запрещено смешивать history ownership back into `TransferSessionCoordinator`
