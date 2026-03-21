# Workpack: Phase 6 Clipboard History Extraction

## 1. Scope

- Вынести local clipboard durable state из `DiscoveryController` в `ClipboardHistoryStore`.
- Переключить `ClipboardSheet` off controller-owned history.
- Не входит: remote browse state, files feature state, transfer session orchestration.

## 2. Source linkage

- `Master phase`: Phase 6
- `Depends on`: `06`, `12`, `01`
- `Unblocks`: `23`, `18`
- `Related workpacks`: `14`

## 3. Problem slice

Master plan фиксирует, что local clipboard history живёт одновременно в repository и controller mirror. Этот slice выделен отдельно, потому что local durable history and remote clipboard projection — разные seams.

## 4. Legacy owner and target owner

- `Legacy owner`: `DiscoveryController`
- `Target owner`: `ClipboardHistoryStore`
- `State seam closed`: local durable clipboard history vs remote clipboard projection
- `Single write authority after cutover`: `ClipboardHistoryStore`

## 5. Source of truth impact

- что сейчас является truth:
  - repository durability plus controller mirror for UI behavior
- что станет truth:
  - `ClipboardHistoryStore`
- что станет projection:
  - grouped/filtered clipboard UI state
- что станет cache:
  - internal dedupe/hash policy inside history store
- что станет temporary bridge only:
  - `ClipboardHistoryAdapter`

## 6. Read/write cutover

- `Legacy read path`: `ClipboardSheet` reads `widget.controller.clipboardHistory`
- `Target read path`: `ClipboardSheet` reads `ClipboardHistoryStore`
- `Read switch point`: sheet no longer depends on `DiscoveryController` for local history
- `Legacy write path`: repository insert/trim plus controller mirror update
- `Target write path`: `ClipboardHistoryStore` writes through repository port only
- `Write switch point`: local capture and history edits stop mutating controller mirror
- `Dual-read allowed?`: yes, for local history parity only
- `Dual-write allowed?`: no

## 7. Temporary bridge

- `Bridge name`: `ClipboardHistoryAdapter`
- `Why it exists`: keep sheet/UI wiring stable while history source switches away from controller
- `Phase introduced`: Phase 6
- `Max allowed lifetime`: through Phase 6 only
- `Deletion phase`: this workpack
- `Forbidden long-term use`: cannot preserve `ClipboardSheet -> DiscoveryController` dependency

## 8. Concrete migration steps

1. freeze local history contract on `ClipboardHistoryStore`
2. move local history reads in `ClipboardSheet` to the store
3. reroute local history writes through store only
4. keep remote clipboard projection explicitly out of this workpack
5. delete adapter after parity proof
6. run repository contract, UI smoke and migration regression tests

## 9. Evidence and source anchors

- `Evidence level`: Confirmed from code
- `Source of truth`:
  - `docs/refactor_master_plan.md`
  - `lib/features/clipboard/presentation/clipboard_sheet.dart` / `final DiscoveryController controller`, `widget.controller.clipboardHistory`
  - `lib/features/discovery/application/discovery_controller.dart` / `_clipboardHistory`, `_handleClipboardQuery`, `_onClipboardCatalog`
  - `lib/features/clipboard/data/clipboard_history_repository.dart` / `listRecent`, `hasHash`, `insert`, `trimToMaxEntries`

## 10. Test gate

- До начала нужны: repository contract tests for `clipboard_history`, UI smoke tests, migration regression tests
- Подтверждают cutover: `ClipboardSheet` works without controller-owned local history
- Hard stop failure:
  - any local history write still updates controller mirror

## 11. Completion criteria

- `ClipboardHistoryStore` is sole local history writer
- `ClipboardSheet` no longer reads local history from `DiscoveryController`
- `ClipboardHistoryAdapter` is deleted

## 12. Deletions unlocked

- `_clipboardHistory`
- `ClipboardHistoryAdapter`

## 13. Anti-regression notes

- запрещено смешивать remote clipboard projection обратно в local history owner
- запрещён repository + controller mirror dual-write under any fallback path
