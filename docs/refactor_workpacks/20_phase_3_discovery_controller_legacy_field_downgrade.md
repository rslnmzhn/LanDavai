# Workpack: Phase 3 DiscoveryController Legacy Field Downgrade

## 1. Scope

- Деградировать и удалить legacy identity/trust fields inside `DiscoveryController` после cutover-ов `04`, `05`, `06`.
- Зафиксировать, какие поля больше не имеют write authority.
- Не входит: ввод новых owners; они already activated by preceding workpacks.

## 2. Source linkage

- `Master phase`: Phase 3
- `Depends on`: `04`, `05`, `06`
- `Unblocks`: `07`, `18`
- `Related workpacks`: `23`

## 3. Problem slice

Master plan требовал отдельный slice на legacy field downgrade/removal внутри `DiscoveryController`. Без него fields вроде `_devicesByIp`, `_aliasByMac`, `_trustedDeviceMacs` остаются скрытыми competing owners даже после nominal owner split.

## 4. Legacy owner and target owner

- `Legacy owner`: `DiscoveryController`
- `Target owner`: no new owner; `DeviceRegistry`, `TrustedLanPeerStore`, `Discovery read/application model` already own their seams
- `State seam closed`: legacy controller fields stop pretending to be truth
- `Single write authority after cutover`: `DeviceRegistry` for identity, `TrustedLanPeerStore` for trust, read model for projection only

## 5. Source of truth impact

- что сейчас является truth:
  - residual controller fields may still shadow identity/trust state
- что станет truth:
  - phase 3 owners only
- что станет projection:
  - any remaining controller fields, if temporarily kept, are projection-only until deletion
- что станет cache:
  - none
- что станет temporary bridge only:
  - none

## 6. Read/write cutover

- `Legacy read path`: residual controller field reads for identity/trust
- `Target read path`: explicit owners and discovery read model
- `Read switch point`: no code path reads these controller fields as primary truth
- `Legacy write path`: controller mutates legacy fields directly
- `Target write path`: writes already moved in `04` and `05`
- `Write switch point`: zero production writes remain to legacy fields
- `Dual-read allowed?`: yes, before deletion proof only
- `Dual-write allowed?`: no

## 7. Temporary bridge

- `No temporary bridge permitted for this workpack`

## 8. Concrete migration steps

1. enumerate legacy identity/trust fields still present in controller
2. prove no production write path targets them
3. reroute any lingering reads to explicit owners/read model
4. downgrade fields to projection-only if temporary retention is still needed
5. delete fields once parity proof is green
6. run identity mapping and UI smoke tests

## 9. Evidence and source anchors

- `Evidence level`: Confirmed from code
- `Source of truth`:
  - `docs/refactor_master_plan.md`
  - `lib/features/discovery/application/discovery_controller.dart` / `_devicesByIp`, `_aliasByMac`, `_trustedDeviceMacs`

## 10. Test gate

- До начала нужны: identity mapping tests, UI smoke tests
- Подтверждают cutover: identity/trust behavior unchanged after controller field downgrade or removal
- Hard stop failure:
  - any production write path still targets the downgraded fields

## 11. Completion criteria

- legacy identity/trust fields are either projection-only or deleted
- no truth ownership remains in `DiscoveryController` for these seams

## 12. Deletions unlocked

- `_devicesByIp` as identity truth
- `_aliasByMac` as identity owner
- `_trustedDeviceMacs` as trust owner

## 13. Anti-regression notes

- запрещено оставить “harmless mirrors” without deletion date
- запрещено reintroduce writes to legacy fields through helper code
