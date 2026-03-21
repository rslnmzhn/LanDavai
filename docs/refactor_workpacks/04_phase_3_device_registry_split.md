# Workpack: Phase 3 DeviceRegistry Split

## 1. Scope

- Вынести device identity ownership из `DiscoveryController` в `DeviceRegistry`.
- Перевести identity writes и identity resolution на новый owner.
- Не входит: discovery UI read-model cutover, trust ownership, legacy field deletion.

## 2. Source linkage

- `Master phase`: Phase 3
- `Depends on`: `01`, `02`, `03`
- `Unblocks`: `06`, `20`
- `Related workpacks`: `05`

## 3. Problem slice

Master plan фиксирует, что `_devicesByIp` и `_aliasByMac` образуют размытый identity owner, конфликтующий с `known_devices`. Этот slice выделен отдельно, потому что он закрывает один конкретный seam: stable device identity vs transient reachability.

## 4. Legacy owner and target owner

- `Legacy owner`: `DiscoveryController`
- `Target owner`: `DeviceRegistry`
- `State seam closed`: device identity keyed by MAC vs reachability keyed by IP
- `Single write authority after cutover`: `DeviceRegistry`
- `Forbidden writers`: `DiscoveryController`, widgets, helper or static functions, direct `DeviceAliasRepository` write paths outside registry boundary
- `Forbidden dual-write paths`: `_devicesByIp` as identity truth in parallel with registry or `known_devices` writes

## 5. Source of truth impact

- что сейчас является truth:
  - `_devicesByIp` for live identity behavior
  - `known_devices` for alias and trust persistence
- что станет truth:
  - `DeviceRegistry`
- что станет projection:
  - `_devicesByIp` only as transient reachability projection
- что станет cache:
  - `known_devices.last_known_ip`
- что станет temporary bridge only:
  - `DeviceIdentityBridge`

## 6. Read/write cutover

- `Legacy read path`: identity lookups from controller maps and helper logic
- `Target read path`: `DeviceRegistry` for identity resolution
- `Read switch point`: non-UI discovery logic stops resolving identity through `_devicesByIp` and `_aliasByMac`
- `Legacy write path`: controller updates maps while repository writes `known_devices`
- `Target write path`: `DeviceRegistry` records seen devices and identity mapping
- `Write switch point`: device observation handling no longer mutates controller maps as primary truth
- `Dual-read allowed?`: yes, for parity checks during migration regression only
- `Dual-write allowed?`: no

## 7. Temporary bridge

- `Bridge name`: `DeviceIdentityBridge`
- `Why it exists`: keep old discovery flows readable while identity authority moves to the registry
- `Phase introduced`: Phase 3
- `Max allowed lifetime`: through Phase 3 only
- `Deletion phase`: `20_phase_3_discovery_controller_legacy_field_downgrade.md`
- `Forbidden long-term use`: cannot preserve `_devicesByIp` as hidden primary identity store

## 8. Concrete migration steps

1. freeze the registry contract over MAC-normalized device identity
2. move device observation writes to `DeviceRegistry`
3. leave `_devicesByIp` only as reachability projection
4. compare old and new identity resolution under parity tests
5. forbid new writes into controller identity fields
6. run `GATE-01`, `GATE-03`, and `GATE-07`
7. capture deletion proof for legacy identity fields

## 9. Evidence and source anchors

- `Evidence level`: Confirmed from code
- `Source of truth`:
  - `docs/refactor_master_plan.md`
  - `lib/features/discovery/application/discovery_controller.dart` / `_devicesByIp`, `_aliasByMac`, `_resolveLocalDeviceMac`
  - `lib/features/discovery/data/device_alias_repository.dart` / `recordSeenDevices`, `normalizeMac`
  - `lib/core/storage/app_database.dart` / `knownDevicesTable`
- `Compatibility anchors`:
  - `known_devices`

## 10. Test gate

- `До начала нужны`: `GATE-01`, `GATE-03`, `GATE-07`
- `Подтверждают cutover`: alias and stable identity still follow normalized MAC after IP change
- `Hard stop failure`: alias or stable identity no longer follows MAC under IP change

## 11. Completion criteria

- `DeviceRegistry` is the sole identity writer
- `_devicesByIp` is not used as stable identity truth
- new code reads stable identity from the registry contract

## 12. Deletions unlocked

- prepares deletion of `_devicesByIp` as primary truth in `20`
- prepares deletion of `_aliasByMac` as identity owner in `20`

## 13. Anti-regression notes

- запрещён новый helper, который обходит registry и пишет в controller maps
- запрещён dual-write controller maps plus registry under production path
