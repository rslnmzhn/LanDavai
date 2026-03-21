# Workpack: Phase 4 Protocol Handlers Split

## 1. Scope

- Разнести scenario dispatch по protocol handlers by scenario.
- Перевести application reactions на handler events.
- Не входит: transport extraction, codec extraction, facade deletion.

## 2. Source linkage

- `Master phase`: Phase 4
- `Depends on`: `07`, `08`
- `Unblocks`: `21`, `14`, `17`
- `Related workpacks`: `06`

## 3. Problem slice

Master plan фиксирует, что discovery, friend, share, clipboard и transfer packet flows живут в одном service-level dispatcher. Этот slice выделен отдельно, потому что scenario dispatch нужно отрезать до Phase 6 feature/session cutovers.

## 4. Legacy owner and target owner

- `Legacy owner`: `LanDiscoveryService`
- `Target owner`: protocol handlers by scenario
- `State seam closed`: scenario-specific protocol reactions separate from transport and UI
- `Single write authority after cutover`: each scenario handler owns only its scenario event publication

## 5. Source of truth impact

- что сейчас является truth:
  - scenario dispatch branches inside `LanDiscoveryService`
- что станет truth:
  - per-scenario handlers
- что станет projection:
  - handler events consumed by application owners
- что станет cache:
  - none
- что станет temporary bridge only:
  - `ProtocolDispatchFacade`

## 6. Read/write cutover

- `Legacy read path`: controller/application reacts to service-level callbacks and broad service surface
- `Target read path`: application owners react to scenario handler events
- `Read switch point`: discovery/share/clipboard/transfer reactions are subscribed to handlers, not to service internals
- `Legacy write path`: scenario send/dispatch decisions are routed through `LanDiscoveryService`
- `Target write path`: scenario handlers own dispatch handoff using transport and codecs
- `Write switch point`: no scenario path uses service as central router
- `Dual-read allowed?`: yes, during handler parity verification only
- `Dual-write allowed?`: no

## 7. Temporary bridge

- `Bridge name`: `ProtocolDispatchFacade`
- `Why it exists`: keep old scenario entrypoints callable while handlers are split out incrementally
- `Phase introduced`: Phase 4
- `Max allowed lifetime`: through Phase 4 only
- `Deletion phase`: `21_phase_4_protocol_dispatch_facade_removal.md`
- `Forbidden long-term use`: cannot preserve mega-service dispatch under a thinner API

## 8. Concrete migration steps

1. inventory scenario flows currently dispatched from `LanDiscoveryService`
2. map each flow to dedicated handler boundary
3. reroute application owners to handler outputs
4. keep `ProtocolDispatchFacade` only as temporary entry shell
5. run protocol compatibility and session continuity tests
6. capture proof that no central service-level dispatch remains

## 9. Evidence and source anchors

- `Evidence level`: Confirmed from code
- `Source of truth`:
  - `docs/refactor_master_plan.md`
  - `lib/features/discovery/data/lan_discovery_service.dart` / discovery, friend, share, thumbnail, clipboard, transfer packet methods
  - `lib/features/discovery/application/discovery_controller.dart` / `_onTransferRequest`, `_onTransferDecision`, `_handleClipboardQuery`, `_handleShareCatalog`

## 10. Test gate

- До начала нужны: protocol compatibility tests, session continuity tests
- Подтверждают cutover: each scenario still reaches the same application reaction with handler boundaries in place
- Hard stop failure:
  - one handler still depends on central service-owned dispatch state

## 11. Completion criteria

- scenario dispatch no longer lives in one service class
- application owners subscribe to handlers, not to mega-service internals

## 12. Deletions unlocked

- unblocks `21` facade removal
- unblocks `14` remote share browser extraction
- unblocks `17` transfer session coordinator split

## 13. Anti-regression notes

- запрещено оставить one-size-fits-all handler coordinator
- запрещено прятать old dispatch branches in helper files and называть это split
