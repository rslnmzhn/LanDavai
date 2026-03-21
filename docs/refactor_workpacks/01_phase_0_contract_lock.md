# Workpack: Phase 0 Contract Lock

## 1. Scope

- Зафиксировать compatibility anchors до любого ownership cutover.
- Установить обязательные test gates для persistence, protocol и identity contracts.
- Не входит: ввод новых owners, переключение read/write paths, удаление legacy кода.

## 2. Source linkage

- `Master phase`: Phase 0
- `Depends on`: none
- `Unblocks`: `02`, `03`, `04`, `05`, `07`, `10`, `13`, `17`
- `Related workpacks`: `19`

## 3. Problem slice

Master plan уже зафиксировал, что локальные изменения опасны из-за отсутствия safety gates. Этот workpack выделен отдельно, потому что без него любые последующие cutover-ы будут слепыми.

## 4. Legacy owner and target owner

- `Legacy owner`: existing writers remain unchanged
- `Target owner`: No new target owner activated in this workpack
- `State seam closed`: compatibility fence around existing contracts
- `Single write authority after cutover`: unchanged from current code; this workpack only freezes it for later migration

## 5. Source of truth impact

- что сейчас является truth:
  - текущие SQLite tables, JSON cache indexes, packet envelopes
- что станет truth:
  - unchanged
- что станет projection:
  - none
- что станет cache:
  - unchanged
- что станет temporary bridge only:
  - none

## 6. Read/write cutover

- `Legacy read path`: unchanged
- `Target read path`: unchanged
- `Read switch point`: none
- `Legacy write path`: unchanged
- `Target write path`: unchanged
- `Write switch point`: none
- `Dual-read allowed?`: not applicable
- `Dual-write allowed?`: not applicable

## 7. Temporary bridge

- `No temporary bridge permitted for this workpack`

## 8. Concrete migration steps

1. зафиксировать repository contracts для `known_devices`, `shared_folder_caches`, `friends`, `app_settings`, `clipboard_history`, `transfer_history`
2. зафиксировать packet identifiers и envelope behavior из `LanDiscoveryService`
3. зафиксировать identity mapping expectations MAC vs IP
4. зафиксировать current shared cache JSON/index semantics
5. собрать matrix обязательных gates в `19_test_gates_matrix.md`
6. прогнать baseline suite
7. зафиксировать, что дальнейшие workpacks не меняют anchors без test proof

## 9. Evidence and source anchors

- `Evidence level`: Confirmed from code
- `Source of truth`:
  - `docs/refactor_master_plan.md`
  - `lib/core/storage/app_database.dart` / `knownDevicesTable`, `sharedFolderCachesTable`, `transferHistoryTable`, `appSettingsTable`, `friendsTable`, `clipboardHistoryTable`
  - `lib/features/discovery/data/lan_discovery_service.dart` / `LANDA_DISCOVER_V1`, `LANDA_HERE_V1`, `LANDA_TRANSFER_REQUEST_V1`, `LANDA_CLIPBOARD_CATALOG_V1`
  - `test/app_settings_repository_test.dart`
  - `test/clipboard_history_repository_test.dart`
  - `test/video_link_share_service_test.dart`

## 10. Test gate

- До начала нужны: none
- Подтверждают cutover: repository contract tests, protocol compatibility tests, identity mapping tests
- Hard stop failure:
  - любое расхождение в table semantics или packet semantics блокирует все последующие workpacks

## 11. Completion criteria

- baseline contract suite существует
- compatibility anchors перечислены и покрыты тестами
- `19_test_gates_matrix.md` заполнен и согласован с master plan

## 12. Deletions unlocked

- Ничего не удаляет напрямую
- Разблокирует безопасное удаление в `20`, `21`, `12`, `23`

## 13. Anti-regression notes

- запрещён “cleanup schema/protocol constants” до фиксации контрактов
- запрещено менять packet shape под видом реорганизации Phase 4
