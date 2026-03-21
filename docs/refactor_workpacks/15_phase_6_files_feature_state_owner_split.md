# Workpack: Phase 6 Files Feature State Owner Split

## 1. Scope

- Вынести explorer navigation, filter, sort, and selection state из `part`-shared files module в explicit owner.
- Разорвать files UI dependence on hidden shared namespace.
- Не входит: preview cache ownership and transfer session orchestration.

## 2. Source linkage

- `Master phase`: Phase 6
- `Depends on`: `12`, `14`
- `Unblocks`: `16`, `23`, `18`
- `Related workpacks`: `22`

## 3. Problem slice

Master plan фиксирует fake decomposition in `file_explorer_*`. Этот slice выделен отдельно, потому что explorer view state — самостоятельный ownership seam и не должен мигрировать вместе с preview cache.

## 4. Legacy owner and target owner

- `Legacy owner`: `file_explorer_*` part graph
- `Target owner`: `Files feature state owner`
- `State seam closed`: explorer navigation and view state vs widget tree and private namespace
- `Single write authority after cutover`: `Files feature state owner`
- `Forbidden writers`: widgets, `DiscoveryController`, `FileExplorerFacade` beyond temporary glue, page-local helpers acting as hidden owners
- `Forbidden dual-write paths`: page-local state and files-owner state mutating the same navigation or selection seam in parallel

## 5. Source of truth impact

- что сейчас является truth:
  - hidden `part`-shared page state and widget-level mutations
- что станет truth:
  - `Files feature state owner`
- что станет projection:
  - explorer tree and list view models
- что станет cache:
  - shared cache data still comes from `SharedCacheCatalog`; preview cache remains separate
- что станет temporary bridge only:
  - `FileExplorerFacade`

## 6. Read/write cutover

- `Legacy read path`: widgets read hidden part-owned state directly
- `Target read path`: widgets read `Files feature state owner`
- `Read switch point`: explorer UI no longer depends on shared private namespace as state owner
- `Legacy write path`: user actions mutate page and part state directly
- `Target write path`: user actions dispatch to files feature owner
- `Write switch point`: path, filter, sort, and selection stop mutating hidden page state as primary truth
- `Dual-read allowed?`: yes, for UI parity verification only
- `Dual-write allowed?`: no

## 7. Temporary bridge

- `Bridge name`: `FileExplorerFacade`
- `Why it exists`: keep explorer entry surface stable while widgets stop binding to part-owned state
- `Phase introduced`: Phase 6
- `Max allowed lifetime`: through Phase 6 only
- `Deletion phase`: `23_phase_6_obsolete_cross_feature_callbacks_removal.md`
- `Forbidden long-term use`: cannot preserve part-based ownership behind wrapper methods

## 8. Concrete migration steps

1. inventory explorer state currently hidden in the `part` namespace
2. move navigation, filter, sort, and selection ownership to explicit owner
3. switch widgets to owner-driven projection reads
4. keep preview cache concerns out of this workpack
5. run `GATE-06` and `GATE-07`
6. capture proof that files UI no longer depends on part-owned truth

## 9. Evidence and source anchors

- `Evidence level`: Confirmed from code
- `Source of truth`:
  - `docs/refactor_master_plan.md`
  - `lib/features/files/presentation/file_explorer_page.dart` / `part` declarations
  - `lib/features/files/presentation/file_explorer/file_explorer_page_state.dart` / `FileExplorerPage`
  - `lib/features/discovery/presentation/discovery_page.dart` / `_openFileExplorer`
- `Compatibility anchors`:
  - shared cache read boundary from `22` must remain intact; this workpack must not write `shared_folder_caches` or index files

## 10. Test gate

- `До начала нужны`: `GATE-06`, `GATE-07`
- `Подтверждают cutover`: explorer works with explicit state owner and without part-owned truth
- `Hard stop failure`: widget behavior still depends on hidden `part` state mutation

## 11. Completion criteria

- explorer navigation, filter, sort, and selection have one explicit owner
- files widgets stop treating the `part` namespace as source of truth

## 12. Deletions unlocked

- part-owned explorer state cluster
- contributes to `23` and later deletion of part-based coupling

## 13. Anti-regression notes

- запрещено переносить old page state into another hidden helper and называть это owner split
- запрещено смешивать preview lifecycle back into files state owner
