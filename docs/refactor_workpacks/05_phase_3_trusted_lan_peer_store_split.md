# Workpack: Phase 3 TrustedLanPeerStore Split

## 1. Scope

- Вынести trust write authority из discovery-owned state в `TrustedLanPeerStore`.
- Отделить LAN trust от friend/internet endpoint semantics.
- Не входит: discovery read model cutover и legacy field deletion.

## 2. Source linkage

- `Master phase`: Phase 3
- `Depends on`: `01`, `02`, `03`
- `Unblocks`: `06`, `20`
- `Related workpacks`: `04`

## 3. Problem slice

Master plan фиксирует, что trust сейчас живёт одновременно в `known_devices.is_trusted` и в controller runtime state. Этот slice выделен отдельно, потому что trust и device identity не должны мигрировать как один пакет.

## 4. Legacy owner and target owner

- `Legacy owner`: `DiscoveryController` plus implicit business ownership in `DeviceAliasRepository`
- `Target owner`: `TrustedLanPeerStore`
- `State seam closed`: trust state separate from identity registry and internet endpoint records
- `Single write authority after cutover`: `TrustedLanPeerStore`

## 5. Source of truth impact

- что сейчас является truth:
  - `known_devices.is_trusted` plus `_trustedDeviceMacs` runtime mirror
- что станет truth:
  - `TrustedLanPeerStore`
- что станет projection:
  - discovery trust badges and trusted-device lists
- что станет cache:
  - none beyond store-owned read snapshots
- что станет temporary bridge only:
  - none

## 6. Read/write cutover

- `Legacy read path`: controller reads `_trustedDeviceMacs`, widgets infer trust from discovery state
- `Target read path`: trust queries via `TrustedLanPeerStore`
- `Read switch point`: all trust checks stop consulting controller-owned mirror as primary truth
- `Legacy write path`: trust toggles route through repository/controller coupling
- `Target write path`: `TrustedLanPeerStore` only
- `Write switch point`: first commit where trust mutation bypasses controller-owned set
- `Dual-read allowed?`: yes, during trust parity validation only
- `Dual-write allowed?`: no

## 7. Temporary bridge

- `No temporary bridge permitted for this workpack`

## 8. Concrete migration steps

1. зафиксировать trust contract keyed by normalized MAC
2. перевести trust writes на `TrustedLanPeerStore`
3. оставить `_trustedDeviceMacs` только как temporary validation mirror until field downgrade workpack
4. отделить trust language from `friend` vocabulary
5. прогнать repository contract and identity mapping tests
6. зафиксировать deletion proof for `_trustedDeviceMacs`

## 9. Evidence and source anchors

- `Evidence level`: Confirmed from code
- `Source of truth`:
  - `docs/refactor_master_plan.md`
  - `lib/features/discovery/data/device_alias_repository.dart` / `loadTrustedMacs`, `setTrusted`, `normalizeMac`
  - `lib/features/discovery/application/discovery_controller.dart` / `_trustedDeviceMacs`
  - `lib/core/storage/app_database.dart` / `knownDevicesTable`

## 10. Test gate

- До начала нужны: repository contract tests for `known_devices`, identity mapping tests
- Подтверждают cutover: trust toggle regression and UI smoke around trusted device presentation
- Hard stop failure:
  - trust state can still be mutated outside `TrustedLanPeerStore`

## 11. Completion criteria

- trust writes go only through `TrustedLanPeerStore`
- `friend` and `trusted device` are not treated as one durable concept
- controller trust mirror is no longer primary truth

## 12. Deletions unlocked

- prepares deletion or downgrade of `_trustedDeviceMacs` in `20`

## 13. Anti-regression notes

- запрещён dual-write to `friends` and `known_devices.is_trusted`
- запрещён helper layer that wraps old repository trust mutation and calls it modularity
