# Workpack: Phase 0 Contract Lock

## 1. Scope

- Зафиксировать compatibility anchors до любого ownership cutover.
- Установить обязательные test gates для persistence, protocol, cache, and identity contracts.
- Не входит: ввод новых owners, переключение read/write paths, удаление legacy кода.

## 2. Source linkage

- `Master phase`: Phase 0
- `Depends on`: none
- `Unblocks`: `02`, `03a`, `03b`, `03`, `04`, `05`, `07`, `08`, `10`, `13`, `17`
- `Related workpacks`: `19`

## 3. Problem slice

Master plan уже зафиксировал, что локальные изменения опасны из-за отсутствия safety gates. Этот workpack выделен отдельно, потому что без него любые последующие cutover-ы будут слепыми.

## 4. Legacy owner and target owner

- `Legacy owner`: existing writers remain unchanged
- `Target owner`: no new target owner activated in this workpack
- `State seam closed`: compatibility fence around current persistence, cache, and wire contracts
- `Single write authority after cutover`: unchanged from current code; this workpack only freezes it for later migration
- `Forbidden writers`: no new writer may be introduced under Phase 0
- `Forbidden dual-write paths`: any new dual-write between current tables, cache files, packet surfaces, and future owners is forbidden before later workpacks explicitly allow parity reads

## 5. Source of truth impact

- что сейчас является truth:
  - current SQLite tables, shared-cache JSON index files, and UDP packet envelopes
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

1. freeze repository contracts for `known_devices`, `shared_folder_caches`, `friends`, `app_settings`, `clipboard_history`, `transfer_history`
2. freeze current UDP packet identifiers and envelope semantics
3. freeze identity mapping expectations MAC vs IP
4. freeze current shared cache JSON/index semantics
5. populate `19_test_gates_matrix.md` with canonical `GATE-*`
6. run baseline gates
7. record that later workpacks may not change anchors without proof

## 9. Evidence and source anchors

- `Evidence level`: Confirmed from code
- `Source of truth`:
  - `docs/refactor_master_plan.md`
  - `lib/core/storage/app_database.dart` / `knownDevicesTable`, `sharedFolderCachesTable`, `transferHistoryTable`, `appSettingsTable`, `friendsTable`, `clipboardHistoryTable`
  - `lib/features/discovery/data/lan_discovery_service.dart` / `LANDA_DISCOVER_V1`, `LANDA_HERE_V1`, `LANDA_TRANSFER_REQUEST_V1`, `LANDA_CLIPBOARD_CATALOG_V1`
  - `test/app_settings_repository_test.dart`
  - `test/clipboard_history_repository_test.dart`
  - `test/video_link_share_service_test.dart`
- `Compatibility anchors`:
  - `known_devices`
  - `shared_folder_caches`
  - `transfer_history`
  - `app_settings`
  - `friends`
  - `clipboard_history`
  - shared cache JSON index files
  - UDP packet envelope semantics
  - handshake identifiers visible from Dart

## 10. Test gate

- `До начала нужны`: none
- `Подтверждают cutover`: `GATE-01`, `GATE-02`, `GATE-03`, `GATE-05` exist and are green before later cutovers start
- `Hard stop failure`: any baseline mismatch in table, cache, or packet semantics blocks all later workpacks

## 11. Completion criteria

- baseline gate matrix exists
- compatibility anchors are enumerated and frozen
- later workpacks can reference canonical `GATE-*` IDs

## 12. Deletions unlocked

- no direct deletions
- enables safe deletion later in `20`, `21`, `12`, and `23`

## 13. Anti-regression notes

- запрещён cleanup schema or protocol constants before contract lock
- запрещено менять packet shape под видом реорганизации Phase 4
