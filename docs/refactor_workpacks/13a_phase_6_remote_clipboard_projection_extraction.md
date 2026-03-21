# Workpack: Phase 6 Remote Clipboard Projection Extraction

## 1. Scope

- Вынести remote clipboard session/projection state из `DiscoveryController` and `ClipboardSheet` controller coupling.
- Сохранить local clipboard durable history outside этого workpack; она закрывается в `13`.
- Не входит: packet handler split, local clipboard persistence, files feature state.

## 2. Source linkage

- `Master phase`: Phase 6
- `Depends on`: `06`, `09`
- `Unblocks`: `23`, `18`
- `Related workpacks`: `13`

## 3. Problem slice

Master plan фиксирует, что `ClipboardSheet` still reaches remote clipboard projection through `DiscoveryController.remoteClipboardEntriesFor`, while remote clipboard packets already belong to protocol/session logic, not local history. Этот slice выделен отдельно, чтобы закрыть session projection seam without polluting `ClipboardHistoryStore`.

## 4. Legacy owner and target owner

- `Legacy owner`: `DiscoveryController`
- `Target owner`: remote clipboard projection boundary
- `State seam closed`: remote clipboard session projection separate from local clipboard durable history
- `Single write authority after cutover`: remote clipboard projection boundary
- `Forbidden writers`: `DiscoveryController`, `ClipboardSheet`, protocol callback code that writes UI state directly, any helper mutating remote clipboard projection outside the target boundary
- `Forbidden dual-write paths`: controller-owned remote clipboard projection in parallel with extracted boundary; remote packet handling mutating both sheet-local state and target projection

`remote clipboard projection boundary`:
- `Derived planning helper, not a new architecture component`

## 5. Source of truth impact

- что сейчас является truth:
  - remote clipboard projection carried through `DiscoveryController` and consumed directly by `ClipboardSheet`
- что станет truth:
  - remote clipboard projection boundary owning session-scoped remote clipboard projection only
- что станет projection:
  - `ClipboardSheet` view state such as selected remote entry
- что станет cache:
  - none
- что станет temporary bridge only:
  - `LegacyDiscoveryFacade`

## 6. Read/write cutover

- `Legacy read path`: `ClipboardSheet` reads `widget.controller.remoteClipboardEntriesFor(...)`
- `Target read path`: `ClipboardSheet` reads remote clipboard projection boundary
- `Read switch point`: sheet no longer depends on controller for remote clipboard entries
- `Legacy write path`: remote clipboard packet handling mutates controller-owned projection
- `Target write path`: remote clipboard packet handlers publish into remote clipboard projection boundary only
- `Write switch point`: no remote clipboard packet updates controller-owned projection state
- `Dual-read allowed?`: yes, during remote projection parity checks only
- `Dual-write allowed?`: no

## 7. Temporary bridge

- `Bridge name`: `LegacyDiscoveryFacade`
- `Why it exists`: keep clipboard entry wiring alive while `ClipboardSheet` stops consuming controller-owned remote projection state
- `Phase introduced`: Phase 3
- `Max allowed lifetime`: through Phase 6 only
- `Deletion phase`: `23_phase_6_obsolete_cross_feature_callbacks_removal.md`
- `Forbidden long-term use`: cannot preserve remote clipboard session state inside discovery controller

## 8. Concrete migration steps

1. inventory remote clipboard read points still bound to `DiscoveryController`
2. define session-scoped remote clipboard projection boundary separate from `ClipboardHistoryStore`
3. route remote clipboard packet outputs from Phase 4 handlers into that boundary
4. switch `ClipboardSheet` to projection-boundary reads
5. keep temporary parity checks only during cutover
6. run `GATE-02`, `GATE-06`, and `GATE-07`
7. capture proof that `ClipboardSheet -> DiscoveryController` remote projection coupling is removable

## 9. Evidence and source anchors

- `Evidence level`: Confirmed from code
- `Source of truth`:
  - `docs/refactor_master_plan.md`
  - `lib/features/clipboard/presentation/clipboard_sheet.dart` / `ClipboardSheet`, `_selectedRemoteIp`, `widget.controller.remoteClipboardEntriesFor`
  - `lib/features/discovery/application/discovery_controller.dart` / `_handleClipboardQuery`, `_onClipboardCatalog`
  - `lib/features/discovery/data/lan_discovery_service.dart` / `LANDA_CLIPBOARD_QUERY_V1`, `LANDA_CLIPBOARD_CATALOG_V1`
- `Compatibility anchors`:
  - `clipboard_history` remains out of scope and must not be repurposed here
  - UDP packet envelope semantics for clipboard packet families
  - handshake identifiers visible from Dart for discovery context around clipboard exchange
- `Missing artifact`:
  - the master plan does not name a dedicated remote clipboard owner
- `Impact of uncertainty`:
  - the exact implementation shape of the session-scoped projection boundary can vary, but ownership rules cannot
- `Safest interim assumption`:
  - treat remote clipboard projection as a session-scoped boundary only and never merge it back into `ClipboardHistoryStore` or `DiscoveryController`

## 10. Test gate

- `До начала нужны`: `GATE-02`, `GATE-06`, `GATE-07`
- `Подтверждают cutover`: remote clipboard list and selection still work without controller-owned projection state
- `Hard stop failure`: any remote clipboard packet path still mutates controller-owned projection or sheet-local hidden truth

## 11. Completion criteria

- remote clipboard projection has one explicit session-scoped owner
- `ClipboardSheet` no longer depends on `DiscoveryController` for remote clipboard entries
- this slice remains separate from local clipboard persistence in `13`

## 12. Deletions unlocked

- remote-projection half of `ClipboardSheet -> DiscoveryController` dependency
- contributes to final `LegacyDiscoveryFacade` deletion in `23`

## 13. Anti-regression notes

- запрещено прятать remote clipboard projection in `ClipboardHistoryStore`
- запрещено оставлять sheet-local fallback collection as hidden second owner
