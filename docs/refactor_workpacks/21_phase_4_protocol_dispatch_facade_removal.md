# Workpack: Phase 4 Protocol Dispatch Facade Removal

## 1. Scope

- Удалить `ProtocolDispatchFacade` после завершения transport, codec, and handler splits.
- Закрыть последний compatibility shell around old `LanDiscoveryService` dispatch surface.
- Не входит: новые handler splits or protocol redesign.

## 2. Source linkage

- `Master phase`: Phase 4
- `Depends on`: `07`, `08`, `09`
- `Unblocks`: `10`, `11`, `14`, `17`, `18`
- `Related workpacks`: `12`

## 3. Problem slice

Master plan требовал отдельный slice на facade removal. Без него Phase 4 вырождается в renaming exercise: old mega-service остаётся центром мира, просто скрытым behind wrapper.

## 4. Legacy owner and target owner

- `Legacy owner`: `ProtocolDispatchFacade`
- `Target owner`: no new owner; transport adapter, packet codecs, and protocol handlers remain active
- `State seam closed`: temporary compatibility surface is removed after target seams are live
- `Single write authority after cutover`: transport adapter, packet codecs, and protocol handlers according to their own workpacks; facade has none
- `Forbidden writers`: any caller that reintroduces facade-mediated routing, `LanDiscoveryService` mega-surface, helper wrappers that keep one compatibility entrypoint alive
- `Forbidden dual-write paths`: facade forwarding in parallel with direct handler or transport entrypoints

## 5. Source of truth impact

- что сейчас является truth:
  - facade may still act as temporary entrypoint to old dispatch surface
- что станет truth:
  - explicit transport, codec, and handler boundaries only
- что станет projection:
  - none
- что станет cache:
  - none
- что станет temporary bridge only:
  - `ProtocolDispatchFacade` until this workpack completes

## 6. Read/write cutover

- `Legacy read path`: callers still tolerate facade-mediated protocol dispatch
- `Target read path`: callers talk directly to handler, transport, and codec boundaries
- `Read switch point`: no caller depends on the facade for protocol interactions
- `Legacy write path`: facade forwards protocol operations into old service-centric surface
- `Target write path`: no facade-mediated writes remain
- `Write switch point`: old service dispatch surface is no longer callable through the facade
- `Dual-read allowed?`: no
- `Dual-write allowed?`: no

## 7. Temporary bridge

- `Bridge name`: `ProtocolDispatchFacade`
- `Why it exists`: temporary shell during Phase 4 decomposition only
- `Phase introduced`: Phase 4
- `Max allowed lifetime`: through Phase 4 only
- `Deletion phase`: this workpack
- `Forbidden long-term use`: cannot survive into Phase 5

## 8. Concrete migration steps

1. verify `07`, `08`, and `09` are complete
2. inventory remaining call sites that still rely on the facade
3. switch those call sites to explicit target boundaries
4. delete the facade and residual forwarding logic
5. run `GATE-02` and `GATE-04`
6. record proof that no protocol path depends on the facade

## 9. Evidence and source anchors

- `Evidence level`: Strong inference from code structure
- `Source of truth`:
  - `docs/refactor_master_plan.md`
  - Phase 4 bridge rules in `docs/refactor_master_plan.md`
  - `lib/features/discovery/data/lan_discovery_service.dart` / broad dispatch surface, packet-family methods, send methods
- `Compatibility anchors`:
  - UDP packet envelope semantics
  - handshake identifiers visible from Dart
  - transfer request and decision packet families
  - share and clipboard packet families visible from Dart
- `Missing artifact`:
  - no code-visible `ProtocolDispatchFacade` exists yet in the current Dart-layer audit
- `Impact of uncertainty`:
  - the exact implementation shape of the temporary facade can vary, but its lifetime closure cannot
- `Safest interim assumption`:
  - any temporary facade introduced by `07`-`09` must be deleted in this workpack and may not absorb handler logic

## 10. Test gate

- `До начала нужны`: `GATE-02`, `GATE-04`
- `Подтверждают cutover`: all packet flows work without facade mediation
- `Hard stop failure`: any production caller still depends on the facade

## 11. Completion criteria

- `ProtocolDispatchFacade` is deleted
- no call path enters protocol dispatch through a compatibility shell

## 12. Deletions unlocked

- `ProtocolDispatchFacade`
- residual dispatch forwarding shell around `LanDiscoveryService`

## 13. Anti-regression notes

- запрещено оставить a smaller facade and call it done
- запрещено move facade forwarding logic into helpers
