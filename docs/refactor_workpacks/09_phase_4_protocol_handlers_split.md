# Workpack: Phase 4 Protocol Handlers Split

## 1. Scope

- Разнести scenario dispatch по protocol handlers by scenario family.
- Stage 1: presence and friend handlers.
- Stage 2: share and clipboard handlers.
- Stage 3: transfer negotiation handlers.
- Не входит: transport extraction, codec extraction, facade deletion.

## 2. Source linkage

- `Master phase`: Phase 4
- `Depends on`: `07`, `08`
- `Unblocks`: `13a`, `14`, `17`, `21`
- `Related workpacks`: `03a`, `06`

## 3. Problem slice

Master plan фиксирует, что discovery, friend, share, clipboard и transfer packet flows живут в одном service-level dispatcher. Этот workpack сохраняет один seam: scenario dispatch ownership. Он остаётся одним файлом только потому, что внутри него жёстко staged decomposition by handler family already fixed above.

## 4. Legacy owner and target owner

- `Legacy owner`: `LanDiscoveryService`
- `Target owner`: protocol handlers by scenario family
- `State seam closed`: scenario-specific protocol reactions separate from transport and UI
- `Single write authority after cutover`: each scenario handler family owns only publication of its own scenario events
- `Forbidden writers`: `LanDiscoveryService` central dispatch branches, widgets, `DiscoveryController` callback code acting as packet handlers
- `Forbidden dual-write paths`: central dispatch handling the same packet family in parallel with extracted handlers; handler families writing the same packet outcome into multiple owners

## 5. Source of truth impact

- что сейчас является truth:
  - scenario dispatch branches inside `LanDiscoveryService`
- что станет truth:
  - per-scenario handlers by family
- что станет projection:
  - handler events consumed by application owners
- что станет cache:
  - none
- что станет temporary bridge only:
  - `ProtocolDispatchFacade`

## 6. Read/write cutover

- `Legacy read path`: controller/application reacts to service-level callbacks and broad service surface
- `Target read path`: application owners react to scenario handler events
- `Read switch point`: presence/friend, share/clipboard, and transfer reactions are subscribed to handlers, not service-internal dispatch branches
- `Legacy write path`: scenario send and dispatch decisions route through `LanDiscoveryService`
- `Target write path`: handler families own scenario dispatch handoff using transport and codecs
- `Write switch point`: no scenario path uses the service as central router
- `Dual-read allowed?`: yes, during handler parity verification only
- `Dual-write allowed?`: no

## 7. Temporary bridge

- `Bridge name`: `ProtocolDispatchFacade`
- `Why it exists`: keep old scenario entrypoints callable while handler families are split out incrementally
- `Phase introduced`: Phase 4
- `Max allowed lifetime`: through Phase 4 only
- `Deletion phase`: `21_phase_4_protocol_dispatch_facade_removal.md`
- `Forbidden long-term use`: cannot preserve mega-service dispatch under a thinner API

## 8. Concrete migration steps

1. inventory packet families currently dispatched from `LanDiscoveryService`
2. extract presence and friend handlers first
3. extract share and clipboard handlers second
4. extract transfer negotiation handlers third
5. reroute application owners to handler outputs after each stage
6. keep `ProtocolDispatchFacade` only as temporary entry shell
7. run `GATE-02` and `GATE-04`
8. capture proof that no central service-level dispatch remains

## 9. Evidence and source anchors

- `Evidence level`: Confirmed from code
- `Source of truth`:
  - `docs/refactor_master_plan.md`
  - `lib/features/discovery/data/lan_discovery_service.dart` / `LANDA_DISCOVER_V1`, `LANDA_HERE_V1`, `LANDA_FRIEND_REQUEST_V1`, `LANDA_FRIEND_RESPONSE_V1`, `LANDA_SHARE_QUERY_V1`, `LANDA_SHARE_CATALOG_V1`, `LANDA_CLIPBOARD_QUERY_V1`, `LANDA_CLIPBOARD_CATALOG_V1`, `LANDA_TRANSFER_REQUEST_V1`, `LANDA_TRANSFER_DECISION_V1`
  - `lib/features/discovery/application/discovery_controller.dart` / `_handleShareCatalog`, `_handleClipboardQuery`, `_onTransferRequest`, `_onTransferDecision`
- `Compatibility anchors`:
  - UDP packet envelope semantics
  - handshake identifiers visible from Dart
  - `friends`
  - `clipboard_history`
  - share catalog packet families visible from Dart

## 10. Test gate

- `До начала нужны`: `GATE-02`, `GATE-04`
- `Подтверждают cutover`: each handler family still emits the same scenario outcome with transport and codec boundaries in place
- `Hard stop failure`: one handler family still depends on central service-owned dispatch state

## 11. Completion criteria

- scenario dispatch no longer lives in one service class
- application owners subscribe to handler families, not mega-service internals
- handler extraction order is completed in the staged sequence above

## 12. Deletions unlocked

- unblocks `21` facade removal
- unblocks `13a`, `14`, and `17`

## 13. Anti-regression notes

- запрещено оставить one-size-fits-all handler coordinator
- запрещено прятать old dispatch branches in helper files and называть это split
