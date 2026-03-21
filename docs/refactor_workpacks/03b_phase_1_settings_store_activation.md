# Workpack: Phase 1 SettingsStore Activation

## 1. Scope

- Активировать `SettingsStore` как owner app settings values.
- Убрать conceptual ownership app settings from unrelated feature repositories.
- Не входит: local peer identity seam itself, discovery read-model cutover, settings UI redesign.

## 2. Source linkage

- `Master phase`: Phase 1
- `Depends on`: `01`, `02`
- `Unblocks`: `20`
- `Related workpacks`: `03a`, `03`

## 3. Problem slice

Master plan фиксирует, что `app_settings` используется как общий storage bucket, а `FriendRepository` already owns one settings key it should not own. Этот slice выделен отдельно, потому что settings ownership должно быть отделено до удаления `_loadSettings` и `_saveSettings` from `DiscoveryController`.

## 4. Legacy owner and target owner

- `Legacy owner`: `DiscoveryController` plus unrelated repositories writing settings-owned values
- `Target owner`: `SettingsStore`
- `State seam closed`: app settings separate from local peer identity and feature runtime state
- `Single write authority after cutover`: `SettingsStore`
- `Forbidden writers`: `DiscoveryController`, `FriendRepository`, widgets, any repository that writes `app_settings` outside `SettingsStore` or `LocalPeerIdentityStore`
- `Forbidden dual-write paths`: direct `app_settings` writes in parallel with `SettingsStore`; settings writes mixed with local identity writes under the same call path

## 5. Source of truth impact

- что сейчас является truth:
  - `AppSettingsRepository` storage surface plus controller/repository business ownership confusion
- что станет truth:
  - `SettingsStore`
- что станет projection:
  - settings screen read models and feature-consumed read-only snapshots
- что станет cache:
  - in-memory settings snapshot inside `SettingsStore`
- что станет temporary bridge only:
  - none

## 6. Read/write cutover

- `Legacy read path`: controller and unrelated repositories load settings directly
- `Target read path`: settings reads go through `SettingsStore`
- `Read switch point`: settings-consuming flows stop treating raw repository access as business owner surface
- `Legacy write path`: controller and unrelated repositories write app settings directly
- `Target write path`: `SettingsStore` only, with `LocalPeerIdentityStore` reserved for local identity seam from `02`
- `Write switch point`: app settings mutations stop bypassing `SettingsStore`
- `Dual-read allowed?`: yes, on the same `app_settings` rows during parity validation only
- `Dual-write allowed?`: no

## 7. Temporary bridge

- `No temporary bridge permitted for this workpack`

## 8. Concrete migration steps

1. freeze the rule that `SettingsStore` owns app settings and `LocalPeerIdentityStore` owns only local identity
2. route settings reads through `SettingsStore`
3. route settings writes through `SettingsStore`
4. block new direct `app_settings` writes from controller and unrelated repositories
5. run `GATE-01`
6. capture proof that `_loadSettings` and `_saveSettings` can be downgraded later in `20`

## 9. Evidence and source anchors

- `Evidence level`: Confirmed from code
- `Source of truth`:
  - `docs/refactor_master_plan.md`
  - `lib/features/settings/data/app_settings_repository.dart` / `AppSettingsRepository`, `load`, `save`
  - `lib/features/discovery/data/friend_repository.dart` / `_localPeerIdKey`, `loadOrCreateLocalPeerId`
  - `lib/features/discovery/application/discovery_controller.dart` / `_loadSettings`, `_saveSettings`
  - `lib/core/storage/app_database.dart` / `appSettingsTable`
- `Compatibility anchors`:
  - `app_settings`

## 10. Test gate

- `До начала нужны`: `GATE-01`
- `Подтверждают cutover`: settings load/save semantics stay stable while controller and unrelated repositories stop acting as owners
- `Hard stop failure`: any feature still writes app settings outside `SettingsStore` or `LocalPeerIdentityStore`

## 11. Completion criteria

- `SettingsStore` is the sole app settings writer
- settings ownership is no longer implicit in `DiscoveryController` or `FriendRepository`
- `20` can remove `_loadSettings` and `_saveSettings` without reopening ownership ambiguity

## 12. Deletions unlocked

- prepares deletion of `_loadSettings` and `_saveSettings` in `20`

## 13. Anti-regression notes

- запрещён новый repository convenience method that writes `app_settings` directly
- запрещено смешивать local identity ownership back into `SettingsStore`
