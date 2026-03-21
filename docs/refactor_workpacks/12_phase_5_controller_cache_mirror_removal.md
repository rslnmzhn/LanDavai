# Workpack: Phase 5 Controller Cache Mirror Removal

## 1. Scope

- Удалить controller mirrors `_ownerSharedCaches` и `_ownerIndexEntriesByCacheId` как owners.
- Закрыть write and refresh paths, которые поддерживают mirrors в `DiscoveryController`.
- Не входит: metadata/index owner activation; это уже выполнено в `10`, `11`, `22`.

## 2. Source linkage

- `Master phase`: Phase 5
- `Depends on`: `10`, `11`, `22`
- `Unblocks`: `14`, `15`, `18`
- `Related workpacks`: `20`

## 3. Problem slice

Master plan фиксирует, что controller mirrors поверх shared cache truth создают competing owners. Этот slice выделен отдельно, потому что deleting mirrors without prior read cutover ломает UI immediately.

## 4. Legacy owner and target owner

- `Legacy owner`: `DiscoveryController` mirrors
- `Target owner`: no new owner; `SharedCacheCatalog` remains the single owner
- `State seam closed`: read-model mirrors no longer pretend to be cache truth
- `Single write authority after cutover`: `SharedCacheCatalog`

## 5. Source of truth impact

- что сейчас является truth:
  - metadata/index truth already moved to catalog, but controller mirrors may still shadow reads
- что станет truth:
  - `SharedCacheCatalog` only
- что станет projection:
  - discovery/files view models rebuilt from catalog queries
- что станет cache:
  - JSON index artifacts under index file store
- что станет temporary bridge only:
  - `SharedCacheCatalogBridge` until deletion in this workpack

## 6. Read/write cutover

- `Legacy read path`: discovery/files still tolerate controller mirror fallback
- `Target read path`: discovery/files read catalog only
- `Read switch point`: all cache consumers complete `22`
- `Legacy write path`: controller refresh/update logic keeps mirrors current
- `Target write path`: no mirror writes remain; only catalog writes persist
- `Write switch point`: all mirror refresh code removed or downgraded to dead code pending deletion
- `Dual-read allowed?`: no, not after workpack start
- `Dual-write allowed?`: no

## 7. Temporary bridge

- `Bridge name`: `SharedCacheCatalogBridge`
- `Why it exists`: provide final parity window before mirror reads are hard cut
- `Phase introduced`: Phase 5
- `Max allowed lifetime`: through Phase 5 only
- `Deletion phase`: this workpack
- `Forbidden long-term use`: cannot survive after mirror removal

## 8. Concrete migration steps

1. verify `22` read cutover is complete
2. block all mirror refresh writes in `DiscoveryController`
3. remove mirror fallback reads
4. delete `SharedCacheCatalogBridge`
5. run shared cache consistency and migration regression tests
6. record proof that controller no longer caches shared cache truth

## 9. Evidence and source anchors

- `Evidence level`: Confirmed from code
- `Source of truth`:
  - `docs/refactor_master_plan.md`
  - `lib/features/discovery/application/discovery_controller.dart` / `_ownerSharedCaches`, `_ownerIndexEntriesByCacheId`, `_loadOwnerCaches`
  - `lib/features/transfer/data/shared_folder_cache_repository.dart` / cache read/write methods now superseded by workpacks `10` and `11`

## 10. Test gate

- До начала нужны: shared cache consistency tests, migration regression tests
- Подтверждают cutover: discovery/files behavior unchanged without controller mirrors
- Hard stop failure:
  - any cache consumer still requires controller mirror fallback

## 11. Completion criteria

- no mirror writes remain in controller
- no mirror reads remain in discovery/files
- `SharedCacheCatalogBridge` is deleted

## 12. Deletions unlocked

- `_ownerSharedCaches`
- `_ownerIndexEntriesByCacheId`
- `SharedCacheCatalogBridge`

## 13. Anti-regression notes

- запрещено оставить dead mirrors “for safety” after read cutover
- запрещено вернуть mirror refresh under UI regression pressure
