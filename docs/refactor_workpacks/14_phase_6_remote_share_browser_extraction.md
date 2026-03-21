# Workpack: Phase 6 Remote Share Browser Extraction

## 1. Scope

- Вынести remote share browse session state из `DiscoveryController` в `RemoteShareBrowser`.
- Отделить session browse state от persisted receiver cache artifacts.
- Не входит: files feature state owner split, preview cache, shared cache writer workpacks.

## 2. Source linkage

- `Master phase`: Phase 6
- `Depends on`: `09`, `12`, `22`
- `Unblocks`: `15`, `23`, `18`
- `Related workpacks`: `10`, `11`

## 3. Problem slice

Master plan фиксирует, что `_remoteShareOptions` одновременно играет роль session state и source for file explorer. Этот slice выделен отдельно, потому что browse session нельзя смешивать с persisted receiver cache catalog.

## 4. Legacy owner and target owner

- `Legacy owner`: `DiscoveryController`
- `Target owner`: `RemoteShareBrowser`
- `State seam closed`: session browse state vs durable receiver cache metadata
- `Single write authority after cutover`: `RemoteShareBrowser` for session browse state

## 5. Source of truth impact

- что сейчас является truth:
  - `_remoteShareOptions` inside discovery controller
- что станет truth:
  - `RemoteShareBrowser`
- что станет projection:
  - files/discovery remote listing projections
- что станет cache:
  - receiver cache metadata/index stays in `SharedCacheCatalog`
- что станет temporary bridge only:
  - `LegacyDiscoveryFacade`

## 6. Read/write cutover

- `Legacy read path`: discovery/files consume controller-owned remote share state
- `Target read path`: discovery/files consume `RemoteShareBrowser` projection
- `Read switch point`: no UI path reads `_remoteShareOptions` directly
- `Legacy write path`: share catalog handling mutates controller-owned remote share state
- `Target write path`: handler/catalog updates mutate `RemoteShareBrowser` only
- `Write switch point`: share catalog event no longer writes into controller session state
- `Dual-read allowed?`: yes, during browse parity checks only
- `Dual-write allowed?`: no

## 7. Temporary bridge

- `Bridge name`: `LegacyDiscoveryFacade`
- `Why it exists`: bridge old discovery-facing remote share entrypoints while consumers switch to browser projection
- `Phase introduced`: Phase 3
- `Max allowed lifetime`: through Phase 6 only
- `Deletion phase`: `23_phase_6_obsolete_cross_feature_callbacks_removal.md`
- `Forbidden long-term use`: cannot preserve controller-owned browse state after cutover

## 8. Concrete migration steps

1. define remote browse session boundary distinct from persisted receiver cache
2. route share catalog events into `RemoteShareBrowser`
3. switch UI reads from controller remote share state to browser projection
4. keep persisted receiver cache reads on `SharedCacheCatalog`
5. run shared cache consistency and UI smoke tests
6. record proof that `_remoteShareOptions` is no longer session truth

## 9. Evidence and source anchors

- `Evidence level`: Confirmed from code
- `Source of truth`:
  - `docs/refactor_master_plan.md`
  - `lib/features/discovery/application/discovery_controller.dart` / `_remoteShareOptions`, `_handleShareCatalog`
  - `lib/features/transfer/data/shared_folder_cache_repository.dart` / `saveReceiverCache`

## 10. Test gate

- До начала нужны: shared cache consistency tests, UI smoke tests
- Подтверждают cutover: remote browse flows still function with session state outside discovery controller
- Hard stop failure:
  - any session browse update still writes to `_remoteShareOptions`

## 11. Completion criteria

- `RemoteShareBrowser` is sole owner of browse session state
- persisted receiver cache and session browse state are no longer conflated

## 12. Deletions unlocked

- `_remoteShareOptions`
- contributes to `23` and `18`

## 13. Anti-regression notes

- запрещено хранить remote browse session inside `SharedCacheCatalog`
- запрещено держать controller fallback writes “temporarily” after cutover
