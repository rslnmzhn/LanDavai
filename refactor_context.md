Общие правила исполнения для этого запуска:

1. Сначала прочитай:
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