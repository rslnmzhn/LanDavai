# Workpack: Phase 6 Preview Cache Owner Split

## 1. Scope

- Вынести preview cache lifecycle из `_MediaPreviewCache` в explicit preview cache owner.
- Отделить preview artifact policy от files navigation state.
- Не входит: files feature navigation state cutover, shared cache ownership, transfer storage redesign.

## 2. Source linkage

- `Master phase`: Phase 6
- `Depends on`: `15`
- `Unblocks`: `23`, `18`
- `Related workpacks`: `11`

## 3. Problem slice

Master plan фиксирует, что `_MediaPreviewCache` — static presentation-global owner. Этот slice выделен отдельно, потому что preview lifecycle — самостоятельный cache seam и не должен мигрировать вместе с explorer navigation state.

## 4. Legacy owner and target owner

- `Legacy owner`: `_MediaPreviewCache`
- `Target owner`: `Preview cache owner`
- `State seam closed`: preview artifact lifecycle vs widget tree and files owner
- `Single write authority after cutover`: `Preview cache owner`
- `Forbidden writers`: widgets, `DiscoveryController`, `TransferStorageService` direct preview writes, `FileExplorerFacade` after owner activation
- `Forbidden dual-write paths`: `_MediaPreviewCache` and preview cache owner both generating or deleting the same preview artifact files

## 5. Source of truth impact

- что сейчас является truth:
  - `_MediaPreviewCache`
- что станет truth:
  - `Preview cache owner`
- что станет projection:
  - preview availability signals used by explorer and viewer UI
- что станет cache:
  - preview artifact files under explicit cache-owner policy
- что станет temporary bridge only:
  - `FileExplorerFacade`

## 6. Read/write cutover

- `Legacy read path`: widgets and query logic read preview status through `_MediaPreviewCache`
- `Target read path`: widgets and query logic read preview status through `Preview cache owner`
- `Read switch point`: no widget reads static preview cache directly
- `Legacy write path`: preview generation and invalidation mutate `_MediaPreviewCache`
- `Target write path`: preview requests and cleanup mutate `Preview cache owner` only
- `Write switch point`: first commit where preview files are not managed by `_MediaPreviewCache`
- `Dual-read allowed?`: yes, for preview parity checks only
- `Dual-write allowed?`: no

## 7. Temporary bridge

- `Bridge name`: `FileExplorerFacade`
- `Why it exists`: keep files UI stable while the preview API moves off the static cache
- `Phase introduced`: Phase 6
- `Max allowed lifetime`: through Phase 6 only
- `Deletion phase`: `23_phase_6_obsolete_cross_feature_callbacks_removal.md`
- `Forbidden long-term use`: cannot keep `_MediaPreviewCache` alive behind the facade

## 8. Concrete migration steps

1. inventory preview request, invalidate, and cleanup paths
2. move preview lifecycle authority to explicit owner
3. switch explorer and viewer preview reads to owner contract
4. block new writes to `_MediaPreviewCache`
5. run `GATE-06` and `GATE-07`
6. record proof that static cache no longer owns preview lifecycle

## 9. Evidence and source anchors

- `Evidence level`: Confirmed from code
- `Source of truth`:
  - `docs/refactor_master_plan.md`
  - `lib/features/files/presentation/file_explorer/media_preview_cache.dart` / `_MediaPreviewCache`
  - `lib/features/files/presentation/file_explorer/local_file_viewer.dart` / `LocalFileViewerPage`
- `Compatibility anchors`:
  - no shared-cache or transfer-history writer changes are permitted in this workpack

## 10. Test gate

- `До начала нужны`: `GATE-06`, `GATE-07`
- `Подтверждают cutover`: preview generation and reuse work without static cache ownership
- `Hard stop failure`: any preview write still goes to `_MediaPreviewCache`

## 11. Completion criteria

- `Preview cache owner` is the sole preview artifact writer
- `_MediaPreviewCache` is no longer an owner, only pending deletion artifact or already gone

## 12. Deletions unlocked

- `_MediaPreviewCache`
- contributes to `23` and `18`

## 13. Anti-regression notes

- запрещено смешивать preview cleanup обратно in files owner or widgets
- запрещено держать static cache for speed after cutover
