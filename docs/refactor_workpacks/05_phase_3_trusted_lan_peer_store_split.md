# Workpack: Phase 3 TrustedLanPeerStore Split

## 1. Scope

- Вынести trust write authority из discovery-owned state в `TrustedLanPeerStore`.
- Отделить LAN trust от friend and internet endpoint semantics.
- Не входит: discovery read-model cutover и legacy field deletion.

## 2. Source linkage

- `Master phase`: Phase 3
- `Depends on`: `01`, `02`, `03`
- `Unblocks`: `06`, `20`
- `Related workpacks`: `04`, `03a`

## 3. Problem slice

Master plan фиксирует, что trust сейчас живёт одновременно в `known_devices.is_trusted` и в controller runtime state. Этот slice выделен отдельно, потому что trust и device identity не должны мигрировать как один пакет.

## 4. Legacy owner and target owner

- `Legacy owner`: `DiscoveryController` plus implicit business ownership in `DeviceAliasRepository`
- `Target owner`: `TrustedLanPeerStore`
- `State seam closed`: trust state separate from identity registry and internet endpoint records
- `Single write authority after cutover`: `TrustedLanPeerStore`
- `Forbidden writers`: `DiscoveryController`, `DiscoveryPage`, `FriendRepository`, direct `DeviceAliasRepository.setTrusted` calls outside the store boundary
- `Forbidden dual-write paths`: `known_devices.is_trusted` writes in parallel with mirrored trust writes into `friends` or controller-owned sets

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
- `Read switch point`: all trust checks stop consulting the controller-owned mirror as primary truth
- `Legacy write path`: trust toggles route through repository and controller coupling
- `Target write path`: `TrustedLanPeerStore` only
- `Write switch point`: first commit where trust mutation bypasses controller-owned set
- `Dual-read allowed?`: yes, during trust parity validation only
- `Dual-write allowed?`: no

## 7. Temporary bridge

- `No temporary bridge permitted for this workpack`

## 8. Concrete migration steps

1. freeze trust contract keyed by normalized MAC
2. move trust writes to `TrustedLanPeerStore`
3. leave `_trustedDeviceMacs` only as temporary validation mirror until `20`
4. separate trust language from `friend` vocabulary
5. run `GATE-01` and `GATE-03`
6. capture deletion proof for `_trustedDeviceMacs`

## 9. Evidence and source anchors

- `Evidence level`: Confirmed from code
- `Source of truth`:
  - `docs/refactor_master_plan.md`
  - `lib/features/discovery/data/device_alias_repository.dart` / `loadTrustedMacs`, `setTrusted`, `normalizeMac`
  - `lib/features/discovery/application/discovery_controller.dart` / `_trustedDeviceMacs`
  - `lib/core/storage/app_database.dart` / `knownDevicesTable`
- `Compatibility anchors`:
  - `known_devices`

## 10. Test gate

- `До начала нужны`: `GATE-01`, `GATE-03`
- `Подтверждают cutover`: trust toggle regression and trusted-device UI behavior remain stable
- `Hard stop failure`: trust state can still be mutated outside `TrustedLanPeerStore`

## 11. Completion criteria

- trust writes go only through `TrustedLanPeerStore`
- `friend` and `trusted device` are not treated as one durable concept
- controller trust mirror is no longer primary truth

## 12. Deletions unlocked

- prepares deletion or downgrade of `_trustedDeviceMacs` in `20`

## 13. Anti-regression notes

- запрещён dual-write to `friends` and `known_devices.is_trusted`
- запрещён helper layer that wraps old trust mutation and calls it modularity
