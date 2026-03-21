# Workpack: Phase 4 Protocol Dispatch Facade Removal

## 1. Scope

- Удалить `ProtocolDispatchFacade` после завершения transport, codec and handler splits.
- Закрыть последний compatibility shell вокруг old `LanDiscoveryService` dispatch surface.
- Не входит: новые handler splits or protocol redesign.

## 2. Source linkage

- `Master phase`: Phase 4
- `Depends on`: `07`, `08`, `09`
- `Unblocks`: `10`, `11`, `14`, `17`, `18`
- `Related workpacks`: `12`

## 3. Problem slice

Master plan требовал отдельный slice на facade removal. Без него Phase 4 вырождается в renaming exercise: old mega-service остаётся центром мира, просто скрытым за wrapper.

## 4. Legacy owner and target owner

- `Legacy owner`: `ProtocolDispatchFacade`
- `Target owner`: no new owner; transport adapter, packet codec set and protocol handlers stay active
- `State seam closed`: temporary compatibility surface is removed after target seams are live
- `Single write authority after cutover`: transport adapter / codecs / handlers according to their slices; facade has none

## 5. Source of truth impact

- что сейчас является truth:
  - facade still may act as entrypoint to old dispatch surface
- что станет truth:
  - explicit transport, codec and handler boundaries
- что станет projection:
  - none
- что станет cache:
  - none
- что станет temporary bridge only:
  - `ProtocolDispatchFacade` until this workpack completes

## 6. Read/write cutover

- `Legacy read path`: callers still tolerate facade-mediated protocol dispatch
- `Target read path`: callers talk directly to handler/transport/codec boundaries
- `Read switch point`: no caller depends on facade for protocol interactions
- `Legacy write path`: facade forwards protocol operations into old service-centric surface
- `Target write path`: no facade-mediated writes remain
- `Write switch point`: old service dispatch surface is no longer callable through facade
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

1. verify transport, codec and handler workpacks are complete
2. inventory remaining call sites that still rely on facade
3. switch those call sites to explicit target boundaries
4. delete facade and residual forwarding logic
5. run protocol compatibility and session continuity tests
6. record proof that no protocol path depends on the facade

## 9. Evidence and source anchors

- `Evidence level`: Strong inference from code structure
- `Source of truth`:
  - `docs/refactor_master_plan.md`
  - Phase 4 bridge rules in `docs/refactor_master_plan.md`
  - `lib/features/discovery/data/lan_discovery_service.dart` / current broad dispatch surface

## 10. Test gate

- До начала нужны: protocol compatibility tests, session continuity tests
- Подтверждают cutover: all packet flows work without facade mediation
- Hard stop failure:
  - any production caller still depends on the facade

## 11. Completion criteria

- `ProtocolDispatchFacade` is deleted
- no call path enters protocol dispatch through compatibility shell

## 12. Deletions unlocked

- `ProtocolDispatchFacade`
- residual dispatch forwarding shell around `LanDiscoveryService`

## 13. Anti-regression notes

- запрещено оставить a smaller facade and call it done
- запрещено move facade forwarding logic into helpers
