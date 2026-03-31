Текущее post-refactor состояние:

- Canonical owners и boundaries сейчас:
  - `DiscoveryReadModel` -> discovery read projection
  - `LocalPeerIdentityStore` -> local peer identity persistence/creation
  - `SharedCacheCatalog` -> shared-cache metadata truth
  - `SharedCacheIndexStore` -> shared-cache index truth
  - `SharedCacheMaintenanceBoundary` -> shared-cache recache/remove/progress
  - `RemoteShareBrowser` -> remote share browse/session truth
  - `RemoteShareMediaProjectionBoundary` -> remote-share thumbnail/media projection
  - `FilesFeatureStateOwner` -> explorer/navigation/view state
  - `PreviewCacheOwner` -> preview lifecycle/cache truth
  - `TransferSessionCoordinator` -> live transfer/session truth
  - `VideoLinkSessionBoundary` -> video-link session commands + projection
  - `DownloadHistoryBoundary` -> download history truth
  - `ClipboardHistoryStore` -> local clipboard history truth
  - `RemoteClipboardProjectionStore` -> remote clipboard projection truth
  - infra ports:
    - `SharedCacheRecordStore`
    - `SharedCacheThumbnailStore`

- `DiscoveryController` не должен снова становиться owner-ом этих seams. Он остаётся
  discovery/friends/video-link shell и thin command/protocol surface там, где это
  ещё реально нужно.
- `DiscoveryPage` не должна собирать feature truth вручную. Если где-то появляется
  callback bundle между features, считай это regression.
- `SharedCacheCatalogBridge` удалён и запрещён архитектурным guard-тестом.
- `DiscoveryPage -> FileExplorerPage.launch(...)` callback bundle удалён и запрещён
  архитектурным guard-тестом.
- `part / part of` запрещён под `lib/` и контролируется guard-тестом.
- `LanPacketCodec` остаётся thin facade; family logic и DTO truth живут в
  dedicated codec files + `lan_packet_codec_models.dart` / `lan_packet_codec_common.dart`.

Общие правила исполнения для workpack/refactor запуска:

1. Сначала прочитай:
- `AGENTS.md`
- `docs/refactor_master_plan.md`
- `docs/refactor_workpacks/00_index.md`
- `docs/refactor_workpacks/18_deletion_wave_map.md`
- `docs/refactor_workpacks/19_test_gates_matrix.md`
- сам целевой workpack
- все workpacks из `Depends on`

2. Работай только в рамках целевого workpack.
Не захватывай соседние seams, даже если они рядом.
Не делай “на будущее” дополнительные рефакторы.
Не делай косметические изменения, массовое форматирование, переименования без
необходимости, переносы по файлам без смысла.

3. До любых изменений проверь:
- выполнены ли зависимости workpack
- выполнены ли required gates
- существует ли уже owner boundary для нужного seam
- не приведёт ли изменение к возврату canonical truth в controller/page/widget/repository
- есть ли в workpack явные:
  - `Legacy owner`
  - `Target owner`
  - `Read switch point`
  - `Write switch point`
  - `Forbidden writers`
  - `Forbidden dual-write paths`
Если этого недостаточно для честной реализации — остановись и верни blocker report
без изменений кода.

4. Изменяй код только там, где это нужно для данного workpack.
Не трогай unrelated code paths.
Не подменяй ownership split file split-ом.
Не прячь старую архитектурную проблему за facade/helper/base-service.
Не расширяй temporary residue, если задача не удаляет его честно.

5. После изменений обязательно:
- прогоняй релевантные тесты для затронутого среза
- затем прогоняй `flutter analyze`
- если есть подходящие widget/integration/unit tests, запускай их
- если тестов нет, не выдумывай их существование; прямо скажи, чего не хватает,
  и всё равно прогоняй максимум доступной проверки

6. Если `flutter analyze` или тесты падают:
- не объявляй workpack завершённым
- либо исправь проблему в пределах scope workpack
- либо верни честный blocker report

7. В финальном ответе обязательно дай:
- `Status: completed / blocked`
- `Workpack`
- `Files changed`
- `Why these files changed`
- `Read path switched?`
- `Write path switched?`
- `Forbidden writers enforced?`
- `Forbidden dual-write paths enforced?`
- `Tests run`
- `flutter analyze result`
- `Deletion unlocked`
- `Remaining risk / uncertainty`

8. Если для выполнения workpack нужны изменения, которые по сути относятся к
другому workpack:
- не делать их молча
- остановиться и явно назвать пересечение
- вернуть blocker report

9. Если owner для seam уже существует:
- читать/писать через него, а не через compatibility mirror
- не оставлять dual-write или dual-read-truth path
- не возвращать скрытый routing через `DiscoveryPage` / `DiscoveryController`,
  если replacement owner-backed path уже есть
