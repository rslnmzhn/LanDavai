# Workpack: Phase 6 Clipboard History Extraction

## 1. Scope

- Вынести local clipboard durable state из `DiscoveryController` в `ClipboardHistoryStore`.
- Переключить local history reads and writes off controller-owned mirror.
- Не входит: remote clipboard projection/session ownership; это закрывает `13a`.

## 2. Source linkage

- `Master phase`: Phase 6
- `Depends on`: `01`, `06`
- `Unblocks`: `23`, `18`
- `Related workpacks`: `13a`

## 3. Problem slice

Master plan фиксирует, что local clipboard history живёт одновременно в repository и controller mirror. Этот slice выделен отдельно, потому что local durable history и remote clipboard projection — разные seams и требуют разного cutover logic.

## 4. Legacy owner and target owner

- `Legacy owner`: `DiscoveryController`
- `Target owner`: `ClipboardHistoryStore`
- `State seam closed`: local durable clipboard history vs remote clipboard projection
- `Single write authority after cutover`: `ClipboardHistoryStore`
- `Forbidden writers`: `DiscoveryController`, `ClipboardSheet`, repository callbacks that mutate UI or controller-owned mirror
- `Forbidden dual-write paths`: repository write plus controller mirror write in the same action path

## 5. Source of truth impact

- что сейчас является truth:
  - repository durability plus controller mirror for UI behavior
- что станет truth:
  - `ClipboardHistoryStore`
- что станет projection:
  - grouped and filtered clipboard UI state
- что станет cache:
  - store-owned dedupe/hash policy only
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
- `Why it exists`: keep sheet/UI wiring stable while local history source switches away from controller
- `Phase introduced`: Phase 6
- `Max allowed lifetime`: through Phase 6 only
- `Deletion phase`: this workpack
- `Forbidden long-term use`: cannot preserve local `ClipboardSheet -> DiscoveryController` history dependency

## 8. Concrete migration steps

1. freeze local history contract on `ClipboardHistoryStore`
2. move local history reads in `ClipboardSheet` to the store
3. reroute local history writes through store only
4. keep remote clipboard projection explicitly out of this workpack
5. delete `ClipboardHistoryAdapter` after parity proof
6. run `GATE-01`, `GATE-06`, and `GATE-07`

## 9. Evidence and source anchors

- `Evidence level`: Confirmed from code
- `Source of truth`:
  - `docs/refactor_master_plan.md`
  - `lib/features/clipboard/presentation/clipboard_sheet.dart` / `ClipboardSheet`, `widget.controller.clipboardHistory`
  - `lib/features/discovery/application/discovery_controller.dart` / `_clipboardHistory`
  - `lib/features/clipboard/data/clipboard_history_repository.dart` / `ClipboardHistoryRepository`, `listRecent`, `hasHash`, `insert`, `trimToMaxEntries`
- `Compatibility anchors`:
  - `clipboard_history`

## 10. Test gate

- `До начала нужны`: `GATE-01`, `GATE-06`, `GATE-07`
- `Подтверждают cutover`: `ClipboardSheet` works without controller-owned local history
- `Hard stop failure`: any local history write still updates controller mirror

## 11. Completion criteria

- `ClipboardHistoryStore` is sole local history writer
- `ClipboardSheet` no longer reads local history from `DiscoveryController`
- `ClipboardHistoryAdapter` is deleted

## 12. Deletions unlocked

- `DiscoveryController._clipboardHistory`
- local-history half of `ClipboardSheet -> DiscoveryController` dependency

## 13. Anti-regression notes

- запрещено смешивать remote clipboard projection обратно в local history owner
- запрещён repository plus controller mirror dual-write under any fallback path
