# Workpack: Phase 5 Shared Cache Index Store Split

## 1. Scope

- Вынести JSON index file ownership из `SharedFolderCacheRepository`.
- Отделить index read and write authority от metadata ownership.
- Не входит: metadata writer cutover, read cutover for files and discovery, mirror removal.

## 2. Source linkage

- `Master phase`: Phase 5
- `Depends on`: `10`
- `Unblocks`: `22`, `12`
- `Related workpacks`: `15`, `16`

## 3. Problem slice

Master plan фиксирует, что JSON index lifecycle и SQLite metadata lifecycle сейчас сшиты. Этот slice выделен отдельно, потому что index artifact — отдельный cache and materialization seam.

## 4. Legacy owner and target owner

- `Legacy owner`: `SharedFolderCacheRepository`
- `Target owner`: index file store
- `State seam closed`: JSON index materialization separate from metadata ownership
- `Single write authority after cutover`: index file store
- `Forbidden writers`: `SharedFolderCacheRepository` broad surface, widgets, `DiscoveryController`, helper code that writes index artifacts directly
- `Forbidden dual-write paths`: old repository index writes in parallel with index file store writes

## 5. Source of truth impact

- что сейчас является truth:
  - repository-owned JSON index read and write methods
- что станет truth:
  - index file store for index artifact lifecycle
- что станет projection:
  - file trees and catalog entry views built from index reads
- что станет cache:
  - JSON index itself remains cache artifact under explicit owner
- что станет temporary bridge only:
  - `SharedCacheCatalogBridge`

## 6. Read/write cutover

- `Legacy read path`: index entries read from repository broad surface
- `Target read path`: index reads come from index file store via `SharedCacheCatalog`
- `Read switch point`: files and discovery consumers stop touching repository-owned index IO directly
- `Legacy write path`: repository builds and writes index files
- `Target write path`: index file store writes index artifacts
- `Write switch point`: `_indexFolder` and related index writes leave repository core
- `Dual-read allowed?`: yes, for parity checks during Phase 5 only
- `Dual-write allowed?`: no

## 7. Temporary bridge

- `Bridge name`: `SharedCacheCatalogBridge`
- `Why it exists`: keep old index reads callable while index artifact ownership is pulled out
- `Phase introduced`: Phase 5
- `Max allowed lifetime`: through Phase 5 only
- `Deletion phase`: `12_phase_5_controller_cache_mirror_removal.md`
- `Forbidden long-term use`: cannot keep repository-owned index writes hidden behind the catalog bridge

## 8. Concrete migration steps

1. inventory index artifact read and write paths
2. move index artifact ownership behind index file store
3. route index reads through catalog-facing query boundary
4. compare old and new index reads under parity checks
5. run `GATE-05`
6. capture proof that repository no longer owns index lifecycle

## 9. Evidence and source anchors

- `Evidence level`: Confirmed from code
- `Source of truth`:
  - `docs/refactor_master_plan.md`
  - `lib/features/transfer/data/shared_folder_cache_repository.dart` / `readIndexEntries`, `_indexFolder`, `buildOwnerSelectionCache`
  - `lib/features/transfer/domain/shared_folder_cache.dart` / `SharedFolderCache`
- `Compatibility anchors`:
  - shared cache JSON index files
  - `shared_folder_caches` remains the metadata anchor around those files

## 10. Test gate

- `До начала нужны`: `GATE-05`
- `Подтверждают cutover`: DB metadata and JSON index stay aligned after update, rebind, and prune paths
- `Hard stop failure`: index file artifact is still written from legacy repository core after cutover

## 11. Completion criteria

- index file store is the only index artifact writer
- index reads are available through the catalog-facing boundary

## 12. Deletions unlocked

- prepares deletion of repository-owned index helpers
- unblocks `22` and `12`

## 13. Anti-regression notes

- запрещён helper split that leaves `_indexFolder` as the real writer
- запрещён dual-write to old and new index file paths
