# Workpack: Phase 5 Shared Cache Metadata Owner

## 1. Scope

- Перевести metadata write authority по `shared_folder_caches` на `SharedCacheCatalog`.
- Отделить metadata ownership от index file IO и controller mirrors.
- Не входит: index store split, files/discovery read cutover, mirror removal.

## 2. Source linkage

- `Master phase`: Phase 5
- `Depends on`: `21`, `01`
- `Unblocks`: `11`, `22`, `12`
- `Related workpacks`: `14`, `15`

## 3. Problem slice

Master plan фиксирует, что `SharedFolderCacheRepository` совмещает persistence, indexing и policy. Этот slice выделен отдельно, потому что metadata single-writer нужно установить до любых read cutover-ов в files/discovery.

## 4. Legacy owner and target owner

- `Legacy owner`: `SharedFolderCacheRepository`
- `Target owner`: `SharedCacheCatalog`
- `State seam closed`: metadata persistence ownership vs index materialization ownership
- `Single write authority after cutover`: `SharedCacheCatalog`

## 5. Source of truth impact

- что сейчас является truth:
  - `shared_folder_caches` rows written through broad repository surface
- что станет truth:
  - `SharedCacheCatalog`
- что станет projection:
  - discovery/files cache lists
- что станет cache:
  - JSON index file remains separate cache artifact
- что станет temporary bridge only:
  - `SharedCacheCatalogBridge`

## 6. Read/write cutover

- `Legacy read path`: repository and controller mirrors read metadata directly
- `Target read path`: metadata queries routed through `SharedCacheCatalog`
- `Read switch point`: initial metadata consumers stop reading repository-owned broad surface directly
- `Legacy write path`: repository methods mutate `shared_folder_caches`
- `Target write path`: `SharedCacheCatalog` is the only metadata writer
- `Write switch point`: create/update/rebind/prune metadata no longer bypass catalog
- `Dual-read allowed?`: yes, until read cutover proof in `22`
- `Dual-write allowed?`: no

## 7. Temporary bridge

- `Bridge name`: `SharedCacheCatalogBridge`
- `Why it exists`: hold old metadata reads together while catalog becomes single writer
- `Phase introduced`: Phase 5
- `Max allowed lifetime`: through Phase 5 only
- `Deletion phase`: `12_phase_5_controller_cache_mirror_removal.md`
- `Forbidden long-term use`: cannot proxy repository writes forever

## 8. Concrete migration steps

1. зафиксировать metadata contract for `shared_folder_caches`
2. route metadata writes through `SharedCacheCatalog`
3. block new direct metadata writes from controller/widgets/repository backdoors
4. keep temporary dual-read only for parity verification
5. run repository contract and shared cache consistency tests
6. capture proof that catalog is sole metadata writer

## 9. Evidence and source anchors

- `Evidence level`: Confirmed from code
- `Source of truth`:
  - `docs/refactor_master_plan.md`
  - `lib/features/transfer/data/shared_folder_cache_repository.dart` / `upsertOwnerFolderCache`, `saveReceiverCache`, `pruneUnavailableOwnerCaches`, `rebindOwnerCachesToMac`
  - `lib/core/storage/app_database.dart` / `sharedFolderCachesTable`

## 10. Test gate

- До начала нужны: repository contract tests, shared cache consistency tests
- Подтверждают cutover: metadata updates stay stable under create/update/prune/rebind flows
- Hard stop failure:
  - any metadata write still bypasses `SharedCacheCatalog`

## 11. Completion criteria

- catalog is sole writer for `shared_folder_caches`
- direct metadata writes from legacy paths are blocked

## 12. Deletions unlocked

- prepares broad repository surface reduction
- unblocks `22` read cutover and `12` mirror removal

## 13. Anti-regression notes

- запрещён facade, который лишь переименует old repository as catalog
- запрещён dual-write repository + catalog for metadata rows
