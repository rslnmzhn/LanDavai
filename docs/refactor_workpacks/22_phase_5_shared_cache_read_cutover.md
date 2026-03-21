# Workpack: Phase 5 Shared Cache Read Cutover

## 1. Scope

- Переключить files/discovery read paths с controller mirrors and direct repository reads на `SharedCacheCatalog`.
- Сделать catalog canonical read boundary before mirror deletion.
- Не входит: metadata/index writer activation and mirror deletion themselves.

## 2. Source linkage

- `Master phase`: Phase 5
- `Depends on`: `10`, `11`, `21`
- `Unblocks`: `12`, `14`, `15`, `18`
- `Related workpacks`: `03`, `06`

## 3. Problem slice

Master plan требовал отдельный read cutover slice для shared cache. Без него mirror removal в `12` становится небезопасным, а files/discovery продолжают читать конкурирующие truths.

## 4. Legacy owner and target owner

- `Legacy owner`: controller mirrors and direct repository reads
- `Target owner`: no new owner; `SharedCacheCatalog` read API becomes canonical
- `State seam closed`: cache reads come from one catalog boundary only
- `Single write authority after cutover`: unchanged from `10`; `SharedCacheCatalog`

## 5. Source of truth impact

- что сейчас является truth:
  - writes already moved to catalog, but reads may still bypass it
- что станет truth:
  - `SharedCacheCatalog` for all cache-facing reads
- что станет projection:
  - files/discovery view models rebuilt from catalog queries
- что станет cache:
  - JSON index files remain index artifacts under explicit owner
- что станет temporary bridge only:
  - `SharedCacheCatalogBridge`

## 6. Read/write cutover

- `Legacy read path`: `DiscoveryController` mirrors and direct repository/index reads
- `Target read path`: `SharedCacheCatalog` query surface
- `Read switch point`: discovery and files no longer read cache state from controller or repository directly
- `Legacy write path`: unchanged from pre-`10`/`11` state for history only; this workpack does not change writer
- `Target write path`: unchanged; `SharedCacheCatalog` remains sole writer
- `Write switch point`: not applicable in this workpack
- `Dual-read allowed?`: yes, until parity proof is complete
- `Dual-write allowed?`: no

## 7. Temporary bridge

- `Bridge name`: `SharedCacheCatalogBridge`
- `Why it exists`: provide short parity window while read consumers move off mirrors and direct repository reads
- `Phase introduced`: Phase 5
- `Max allowed lifetime`: through Phase 5 only
- `Deletion phase`: `12_phase_5_controller_cache_mirror_removal.md`
- `Forbidden long-term use`: cannot remain as permanent read multiplexer

## 8. Concrete migration steps

1. inventory every files/discovery read path still bypassing catalog
2. switch those reads to catalog queries
3. keep temporary dual-read only for parity verification
4. block new direct repository/mirror reads
5. run shared cache consistency and UI smoke tests
6. record proof that mirror removal is now safe

## 9. Evidence and source anchors

- `Evidence level`: Confirmed from code
- `Source of truth`:
  - `docs/refactor_master_plan.md`
  - `lib/features/discovery/application/discovery_controller.dart` / `_ownerSharedCaches`, `_ownerIndexEntriesByCacheId`
  - `lib/features/transfer/data/shared_folder_cache_repository.dart` / `readIndexEntries`, `listCaches`
  - `lib/features/files/presentation/file_explorer_page.dart` / files feature entry boundary

## 10. Test gate

- До начала нужны: shared cache consistency tests, UI smoke tests
- Подтверждают cutover: discovery/files behave identically when reading from catalog only
- Hard stop failure:
  - any production read path still bypasses catalog after claimed switch

## 11. Completion criteria

- files and discovery read cache state only through `SharedCacheCatalog`
- `SharedCacheCatalogBridge` is only temporary and ready for deletion in `12`

## 12. Deletions unlocked

- unblocks `12` mirror removal
- contributes to deletion of broad repository read surface

## 13. Anti-regression notes

- запрещено оставлять mirror fallback under feature flags
- запрещено introduce direct repository reads “for performance” after cutover
