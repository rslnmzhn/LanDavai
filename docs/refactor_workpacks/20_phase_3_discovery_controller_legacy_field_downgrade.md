# Workpack: Phase 3 DiscoveryController Legacy Field and Method Downgrade

## 1. Scope

- Деградировать и удалить legacy identity, trust, peer, and settings-owned artifacts inside `DiscoveryController`.
- Закрыть остаточные writes to `_devicesByIp`, `_aliasByMac`, `_trustedDeviceMacs`, `_friends`, `_loadSettings`, and `_saveSettings`.
- Не входит: Phase 6 history, clipboard, files, or remote-share runtime seams.

## 2. Source linkage

- `Master phase`: Phase 3
- `Depends on`: `03a`, `03b`, `04`, `05`, `06`
- `Unblocks`: `07`, `23`, `18`
- `Related workpacks`: `02`

## 3. Problem slice

Master plan требовал отдельный slice на legacy field downgrade inside `DiscoveryController`. Audit показал, что без этого package теряет deletion traceability for `_friends`, `_loadSettings`, and `_saveSettings`, not only identity/trust fields.

## 4. Legacy owner and target owner

- `Legacy owner`: `DiscoveryController`
- `Target owner`: no new owner; `DeviceRegistry`, `TrustedLanPeerStore`, `InternetPeerEndpointStore`, `SettingsStore`, and `Discovery read/application model` already own their seams
- `State seam closed`: legacy controller fields and settings methods stop pretending to be truth or write entrypoints
- `Single write authority after cutover`: explicit owners above; the controller owns no domain write authority for these seams
- `Forbidden writers`: `DiscoveryController`, helper code, widgets, legacy callbacks that reintroduce writes to downgraded fields or settings methods
- `Forbidden dual-write paths`: downgraded controller fields or methods in parallel with the explicit owners listed above

## 5. Source of truth impact

- что сейчас является truth:
  - residual controller fields and methods may still shadow identity, trust, internet endpoint, and settings ownership
- что станет truth:
  - explicit owners from Phase 1 and Phase 3 only
- что станет projection:
  - any controller fields retained temporarily are projection-only and deletion-bound
- что станет cache:
  - none
- что станет temporary bridge only:
  - `PeerVocabularyAdapter`
  - `DeviceIdentityBridge`

## 6. Read/write cutover

- `Legacy read path`: residual controller field reads for identity, trust, endpoint, and settings-owned state
- `Target read path`: explicit owners and discovery read model
- `Read switch point`: no code path reads these controller artifacts as primary truth
- `Legacy write path`: controller mutates legacy fields or calls `_loadSettings` / `_saveSettings` as business-owner surface
- `Target write path`: writes already moved in `02`, `03a`, `03b`, `04`, and `05`
- `Write switch point`: zero production writes remain to downgraded fields and methods
- `Dual-read allowed?`: yes, before deletion proof only
- `Dual-write allowed?`: no

## 7. Temporary bridge

- `Bridge name`: `PeerVocabularyAdapter`, `DeviceIdentityBridge`
- `Why it exists`: short-lived compatibility shells from earlier workpacks only
- `Phase introduced`: Phase 1 and Phase 3
- `Max allowed lifetime`: through Phase 3 only
- `Deletion phase`: this workpack
- `Forbidden long-term use`: cannot preserve controller-owned truth or merged peer semantics after field and method downgrade

## 8. Concrete migration steps

1. enumerate legacy controller artifacts still present for identity, trust, peers, and settings
2. prove no production write path targets them
3. reroute any lingering reads to explicit owners and discovery read model
4. downgrade fields and methods to projection-only if temporary retention is still needed
5. delete `PeerVocabularyAdapter` and `DeviceIdentityBridge`
6. run `GATE-01`, `GATE-03`, `GATE-06`, and `GATE-07`
7. record proof that the downgraded controller artifacts no longer act as owners

## 9. Evidence and source anchors

- `Evidence level`: Confirmed from code
- `Source of truth`:
  - `docs/refactor_master_plan.md`
  - `lib/features/discovery/application/discovery_controller.dart` / `_devicesByIp`, `_aliasByMac`, `_trustedDeviceMacs`, `_friends`, `_loadSettings`, `_saveSettings`
  - `lib/core/storage/app_database.dart` / `knownDevicesTable`, `friendsTable`, `appSettingsTable`
- `Compatibility anchors`:
  - `known_devices`
  - `friends`
  - `app_settings`

## 10. Test gate

- `До начала нужны`: `GATE-01`, `GATE-03`, `GATE-06`, `GATE-07`
- `Подтверждают cutover`: identity, trust, peer, and settings flows still work after controller downgrade
- `Hard stop failure`: any production read or write path still relies on the downgraded controller artifacts as truth

## 11. Completion criteria

- `_devicesByIp`, `_aliasByMac`, `_trustedDeviceMacs`, and `_friends` are either projection-only or deleted
- `_loadSettings` and `_saveSettings` are no longer business-owner entrypoints
- `PeerVocabularyAdapter` and `DeviceIdentityBridge` are deleted

## 12. Deletions unlocked

- `DiscoveryController._devicesByIp` as identity truth
- `DiscoveryController._aliasByMac` as identity owner
- `DiscoveryController._trustedDeviceMacs` as trust owner
- `DiscoveryController._friends` as peer owner
- `DiscoveryController._loadSettings`
- `DiscoveryController._saveSettings`
- `PeerVocabularyAdapter`
- `DeviceIdentityBridge`

## 13. Anti-regression notes

- запрещено оставлять harmless mirrors without a deletion path
- запрещено reintroduce writes to downgraded controller artifacts through helper code
