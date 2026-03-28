Текущее post-refactor состояние:

- Canonical owners по вынесенным seams сейчас такие:
  - `SharedCacheCatalog` -> metadata truth
  - `SharedCacheIndexStore` -> index truth
  - `RemoteShareBrowser` -> remote share browse session truth
  - `FilesFeatureStateOwner` -> explorer/navigation/view state
  - `PreviewCacheOwner` -> preview lifecycle/cache truth
  - `TransferSessionCoordinator` -> live transfer/session truth
  - `DownloadHistoryBoundary` -> download history truth
  - `ClipboardHistoryStore` -> local clipboard history truth
  - `RemoteClipboardProjectionStore` -> remote clipboard projection/loading truth
- `DiscoveryController` больше не должен становиться owner-ом этих seams обратно. Он остаётся discovery/friends/video-link shell и thin command/protocol surface там, где это ещё реально нужно.
- `DiscoveryPage` больше не должна собирать feature truth вручную. Если где-то остался callback bundle между features, считай это cleanup debt, а не допустимым target pattern.
- `SharedCacheCatalogBridge` всё ещё жив как temporary read-side residue. Не расширяй его роль и не копируй этот паттерн в новый код.
- `DiscoveryPage -> FileExplorerPage.launch(...)` recache/remove/progress callback bundle всё ещё является известным residual cleanup seam. Не считай его новой нормой и не строй поверх него дополнительные зависимости.
- `VideoLinkShareService.activeSession` остаётся отдельным seam и не должен молча поглощаться `TransferSessionCoordinator`.
- Оставшиеся `part / part of` в files presentation допустимы только как leaf viewer/widget detail. Не возвращай туда feature-wide ownership.

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
Не делай косметические изменения, массовое форматирование, переименования без необходимости, переносы по файлам без смысла.

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
Если этого недостаточно для честной реализации — остановись и верни blocker report без изменений кода.

4. Изменяй код только там, где это нужно для данного workpack.
Не трогай unrelated code paths.
Не подменяй ownership split file split-ом.
Не прячь старую архитектурную проблему за facade/helper/base-service.
Не расширяй temporary residue (`SharedCacheCatalogBridge`, compatibility callbacks, bridge-like helpers), если задача не удаляет его честно.

5. После изменений обязательно:
- прогоняй релевантные тесты для затронутого среза
- затем прогоняй `flutter analyze`
- если есть подходящие widget/integration/unit tests, запускай их
- если тестов нет, не выдумывай их существование; прямо скажи, чего не хватает, и всё равно прогоняй максимум доступной проверки

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

8. Если для выполнения workpack нужны изменения, которые по сути относятся к другому workpack:
- не делать их молча
- остановиться и явно назвать пересечение
- вернуть blocker report

9. Если owner для seam уже существует:
- читать/писать через него, а не через compatibility mirror
- не оставлять dual-write или dual-read-truth path
- не возвращать скрытый routing через `DiscoveryPage` / `DiscoveryController`, если replacement owner-backed path уже есть
