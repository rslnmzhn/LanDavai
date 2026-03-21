# Workpack: Phase 4 Transport Adapter Extraction

## 1. Scope

- Вынести UDP transport lifecycle из `LanDiscoveryService`.
- Отделить socket ownership от scenario semantics.
- Не входит: packet codec split, handler split, facade deletion.

## 2. Source linkage

- `Master phase`: Phase 4
- `Depends on`: `06`, `01`
- `Unblocks`: `09`, `21`
- `Related workpacks`: `08`

## 3. Problem slice

Master plan фиксирует, что `LanDiscoveryService` одновременно держит transport lifecycle и scenario logic. Этот slice отдельный, потому что socket ownership должен быть отрезан до packet/handler cutover.

## 4. Legacy owner and target owner

- `Legacy owner`: `LanDiscoveryService`
- `Target owner`: transport adapter
- `State seam closed`: socket lifecycle vs scenario semantics
- `Single write authority after cutover`: transport adapter for UDP lifecycle

## 5. Source of truth impact

- что сейчас является truth:
  - `LanDiscoveryService` owns start/stop/send transport lifecycle
- что станет truth:
  - transport adapter
- что станет projection:
  - none
- что станет cache:
  - none
- что станет temporary bridge only:
  - `ProtocolDispatchFacade`

## 6. Read/write cutover

- `Legacy read path`: services and handlers depend on `LanDiscoveryService` transport state implicitly
- `Target read path`: transport state is exposed via adapter boundary only
- `Read switch point`: packet handling no longer reads raw transport lifecycle from `LanDiscoveryService`
- `Legacy write path`: `start` / low-level send logic mutates transport inside `LanDiscoveryService`
- `Target write path`: transport adapter owns start/stop/send raw packet path
- `Write switch point`: first commit where UDP lifecycle no longer mutates inside scenario service core
- `Dual-read allowed?`: no
- `Dual-write allowed?`: no

## 7. Temporary bridge

- `Bridge name`: `ProtocolDispatchFacade`
- `Why it exists`: keep old service surface alive while transport is pulled out from below
- `Phase introduced`: Phase 4
- `Max allowed lifetime`: through Phase 4 only
- `Deletion phase`: `21_phase_4_protocol_dispatch_facade_removal.md`
- `Forbidden long-term use`: cannot hide old transport ownership behind a new name

## 8. Concrete migration steps

1. выделить raw UDP lifecycle boundary
2. перенести start/stop/send ownership to transport adapter
3. оставить scenario layer dependent on transport contract only
4. прогнать protocol compatibility tests
5. зафиксировать proof that socket lifecycle no longer lives in `LanDiscoveryService`

## 9. Evidence and source anchors

- `Evidence level`: Confirmed from code
- `Source of truth`:
  - `docs/refactor_master_plan.md`
  - `lib/features/discovery/data/lan_discovery_service.dart` / `start`, packet send methods, UDP-related surface

## 10. Test gate

- До начала нужны: protocol compatibility tests
- Подтверждают cutover: no packet flow regression with transport ownership moved out
- Hard stop failure:
  - UDP lifecycle still leaks from `LanDiscoveryService` as operational truth

## 11. Completion criteria

- transport lifecycle lives behind adapter contract
- scenario code no longer owns raw socket lifecycle

## 12. Deletions unlocked

- unblocks `21` facade removal
- prepares deletion of residual transport internals from `LanDiscoveryService`

## 13. Anti-regression notes

- запрещён facade-only “split” without moving socket ownership
- запрещено смешивать transport retries with handler logic in the adapter
