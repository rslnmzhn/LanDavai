# Landa Roadmap

Рабочий роадмап: баги к фиксам, снижение веса приложения и отвязка веса
приложения от переданных файлов. Порядок внутри разделов — приоритет.

Формат: чек-боксы. Задача закрывается отметкой `[x]` в PR, который её
выполняет (рядом остаётся ссылка на PR/коммит).

---

## 1. Баги к фиксам

- [x] **B-01 (HIGH). Orphaned `incoming_temp`: приёмник вечно копит временные файлы** — закрыто этим коммитом: startup-sweep (`IncomingTempSweeper`) + очистка staging в error-path completion boundary.
  - Приём на Android (и fallback-пути на десктопе) пишет во
    `<app_support>/Landa/Landa/incoming_temp`
    (`lib/features/transfer/data/transfer_storage_service.dart:38`). Удаление
    source-файлов происходит только при **успешной** публикации
    (`transfer_storage_service.dart:236-239`). При падении публикации
    (`StateError` в
    `lib/features/transfer/application/incoming_transfer_completion_boundary.dart:237`),
    обрыве передачи, kill приложения посреди передачи — файлы остаются
    навсегда. Отдельно: удаление идёт по одному файлу, и падение посреди
    батча оставляет все остальные файлы батча в temp.
  - Fix direction: sweep-очистка `incoming_temp` при старте приложения +
    очистка `result.savedPaths` в error-path completion boundary +
    batch-tolerant удаление.

- [x] **B-02 (HIGH). Нет read/idle timeout при активном стриминге payload** — закрыто этим коммитом: idle-watchdog на время pending socket reads (`armIdleWatchdog`/`disarmIdleWatchdog`), дефолт 30 с, инъекция через `receiveIdleTimeoutOverride`.
  - Таймер отменяется сразу после accept соединения
    (`file_transfer_service.dart:210-212`), а `socket_exact_reader.readExact`
    ждёт бесконечно. Отвал Wi-Fi без RST → сессия приёма висит вечно,
    состояние не переходит в `failed`.
  - Fix direction: idle-timeout, который переarmed-ится после каждого
    успешного chunk read, вместо полной отмены после accept.

- [x] **B-03 (HIGH). MediaStore publish: неверные пути в истории + утечка pending rows (Android)** — закрыто этим коммитом: rollback pending row в catch-ветке, резолв фактического пути через query `DATA`, pre-Q удаление partial target.
  - `copyFileToDownloadsScoped`
    (`android/app/src/main/kotlin/com/example/landa/MainActivity.kt:359`)
    возвращает путь `"$appFolderName/$normalized"`, игнорируя
    авто-переименование MediaStore при коллизии DISPLAY_NAME
    (`file.txt` → `file (1).txt`); история загрузок и уведомления начинают
    указывать на несуществующие пути. При ошибке копирования вставленная
    строка остаётся с `IS_PENDING=1` без cleanup URI. Pre-Q ветка
    (`copyTo(overwrite=false)`) оставляет частично записанные файлы.
  - Fix direction: после вставки резолвить фактический путь через query
    (`DATA` / DocumentsContract), в catch-ветке удалять pending row, pre-Q —
    писать через temp+rename или чистить partial target.

- [x] **B-04 (MEDIUM). Тест `share_access_snapshot_applied`: гонка flush диагностического лога** — закрыто этим коммитом: flush-barrier `idle` в `SharedDownloadDiagnosticLogStore`, тест ждёт барьер вместо гонки с файлом, ошибки записи логируются вместо молчаливого проглатывания.
  - `test/transfer_session_coordinator_test.dart:2950-2962` ждёт только стадию
    `share_access_request_sent`, затем ассертит более поздние стадии, которые
    пишутся fire-and-forget (`remote_share_access_session_boundary.dart:392,400`);
    тест читает файл лога напрямую и гоняет с незафлушенными writes
    (`shared_download_diagnostic_log_store.dart`, read-modify-write с
    `flush:true`, ошибки глотаются через `.catchError((_) {})`). Сейчас тест
    детерминированно красный и на main; это же место означает молчаливую
    потерю диагностических событий в проде.
  - Fix direction: expose flush-barrier (`Future<void> get idle`) из log
    store, тест ждёт barrier; плюс перестать глотать ошибки записи.

- [ ] **B-05 (MEDIUM). Тест «large direct transfer manifest»: таймаут 2 минуты на 15000 файлов**
  - `test/file_transfer_service_test.dart:205` создаёт 15000 файлов;
    receive-loop на каждый файл делает ~10–15 syscalls (double exists+stat в
    verify, exists-loop аллокатора
    `transfer_destination_path_allocator.dart:22-36`, рекурсивный create
    parent, rename). Под нагрузкой не укладывается в дефолтный таймаут теста;
    teardown падает с «directory not empty». Это симптом реальной медленности
    bulk-receive на десктопе.
  - Fix direction: ускорить hot path (меньше stat-проходов, батч-create
    parents), тесту поднять timeout явно; замерить вклад Windows Defender
    отдельно.

- [x] **B-06 (MEDIUM). `LanNearbyTransportAdapter.dispose()`: event-after-close race** — закрыто этим коммитом: контроллер событий закрывается после завершения disconnect + guard `_emit` на добавление после dispose; регрессионный тест на teardown под трафиком.
  - `lan_nearby_transport_adapter.dart:336-343`: `unawaited(disconnect())`,
    затем синхронный `_events.close()`; асинхронные socket-обработчики позже
    добавляют event в закрытый broadcast controller → спорадический
    `StateError: Cannot add event after closing` при teardown
    nearby-transfer.
  - Fix direction: закрывать controller после завершения disconnect, либо
    guard-флаг на add.

- [x] **B-07 (MEDIUM). `share_intent` cache никогда не чистится** — закрыто этим коммитом: удаление staging-копий через канал `discardSharedFiles` при очистке share (успешная отправка/отказ пользователя) + age-sweep каталога `<cache>/share_intent` при старте (24 ч).
  - `MainActivity.kt:286` копирует share-intent контент в
    `cacheDir/share_intent`; дальше пути живут только в памяти
    (`share_receive_boundary.dart`, `share_intent_adapter.dart`), удаления
    нет нигде. Каждый «поделиться → Landa» навсегда растит cache-каталог.
  - Fix direction: удалять скопированные файлы после успешного старта
    отправки + age-based sweep каталога при старте.

- [ ] **B-08 (LOW). Destination allocator TOCTOU**
  - `transfer_destination_path_allocator.dart:22-51`: exists-check затем
    rename без атомарного claim. Параллельные приёмы в одну папку могут
    схлопнуться на одном имени и уронить элемент.
  - Fix direction: создавать claim эксклюзивно (create пустой `.claim` файл с
    `FileMode.exclusive` / rename-first стратегия).

- [ ] **B-09 (LOW). Bare-catch скрывает провалы очистки**
  - Глотание ошибок удаления без телеметрии:
    `transfer_failed_file_cleanup.dart:10,20`,
    `outgoing_transfer_send_file_ops.dart:103`,
    `remote_share_access_file_cleanup.dart:8`,
    `file_transfer_service.dart:642`, `preview_cache_owner.dart:747`.
    Провал cleanup = тихий рост мусора без единого лога.
  - Fix direction: заменить на debug-log с путём и ошибкой; для temp-зон
    добавить счётчик неудачных удалений в диагностику.

- [ ] **B-10 (LOW). Небольшое: unbounded `terminalDownloadNotificationIds`**
  - `MainActivity.kt:43` множество id терминальных download-уведомлений
    никогда не чистится → медленный рост памяти в долгих фоновых сессиях.
  - Fix direction: LRU/ограничение размера или TTL.

### Verified clean (трогать не нужно)

Проверено и признано корректным: lifecycle timers discovery, multicast lock
pairing, framing/close/error в `SocketExactReader`, периодические таймеры
`NearbyTransferSessionStore`, удаление изображений clipboard history, удаление
index+thumbnails при cache removal, server lifecycle `VideoLinkShareService`
и auth на `/stream`, виртуальные path joins (producer/consumer пары),
defensive consumption `getPublicDownloadsPath`.

---

## 2. Снижение веса приложения

Цель: заметно уменьшить размер устанавливаемого пакета (APK/AAB) и объём
app-support данных, не теряя функциональность.

- [ ] **S-01 (HIGH). Аудит media_kit libs: главный кандидат на утяжеление**
  - В `pubspec.yaml` подключены `media_kit_libs_windows_video`,
    `media_kit_libs_linux`, `media_kit_libs_macos_video`,
    `media_kit_libs_ios_video`, `media_kit_libs_android_video`. Каждая тянет
    нативные декодеры (десятки МБ на платформу).
  - Вопросы к ответу перед фиксой: реально ли используется видео-плеер на
    всех заявленных платформах; можно ли оставить `media_kit` только там,
    где он нужен; не дублируется ли функциональность с уже подключённым
    `video_player`.
  - Действие: замерить вес APK/AAB до/после отключения каждой lib
    (`flutter build apk --analyze-size`), зафиксировать таблицу здесь.

- [ ] **S-02 (HIGH). Android App Bundle + per-ABI split**
  - Сейчас релизы собираются одним APK (`android/app/build.gradle.kts` без
    `splits`/ABI-фильтров). NDK-библиотеки всех ABI кладутся в один пакет.
  - Действие: переход на `flutter build appbundle` (Play) и/или
    `--split-per-abi` (sideload-каналы) убирает чужие архитектуры из пакета —
    типичная экономия 30–50% нативной части.

- [ ] **S-03 (MEDIUM). `--obfuscate --split-debug-info` для release**
  - Release-сборки без обфускации несут полные symbol'ы Dart snapshot'а.
  - Действие: `flutter build apk --obfuscate
    --split-debug-info=build/symbols`; сохранить артефакты для symbolication
    релизов.

- [ ] **S-04 (MEDIUM). Ревизия тяжёлых Dart-зависимостей**
  - Кандидаты на проверку «используется ли вообще»: `super_clipboard` при
    собственном clipboard-стеке проекта; `image` (тяжёлый) — какие операции
    реально нужны; `mobile_scanner` vs `qr_flutter`; `video_player` +
    `video_thumbnail` vs `media_kit` — не держим ли два видео-стека
    одновременно.
  - Правило: зависимость остаётся только при прямом product need (см. Code
    Quality Contract в AGENTS.md).

- [ ] **S-05 (LOW). Assets-гигиена**
  - Сейчас в assets только переводы и tray-иконка — это ок. Держать порог:
    никаких крупных шрифтов/картинок целиком, шрифты subsetting (Manrope,
    JetBrains Mono — только используемые weights/наборы).

- [ ] **S-06 (LOW). App-support данные: превью-кэш и диагностика**
  - Уже есть policy-cleanup превью (`cleanupPreviewCache`), но стоит
    добавить показ пользователю занятого места кэшем в настройках + кнопку
    «очистить»; ротацию debug-логов (`<app_support>/Landa/logs/debug.log`)
    по возрасту/размеру.

---

## 3. Отвязка веса приложения от переданных файлов

### Текущее поведение (зафиксировано по коду)

**Android.** Приём идёт в песочницу:
`getApplicationSupportDirectory()/Landa/Landa/incoming_temp`
(`transfer_storage_service.dart:34-41`), затем при успехе файлы публикуются
в публичный `Download/Landa/...` через MediaStore
(`MainActivity.kt:copyFileToDownloadsScoped`, вызов из
`incoming_transfer_completion_boundary.dart:230`) и удаляются из temp
(`transfer_storage_service.dart:236-239`).

**Windows/Linux.** Приём сразу в пользовательские Downloads:
`getDownloadsDirectory()/Landa` (`transfer_storage_service.dart:44-48`).

**Что это значит для веса.**

- APK-вес (размер самого приложения) переданные файлы **не увеличивают ни на
  одном Android 10+**: `incoming_temp` живёт в app-support storage
  (internal app data), а не в APK; публикация выносит файлы из песочницы.
  ОС считает их частью «App size» в системных настройках лишь пока они лежат
  в `incoming_temp` (то есть в идеале секунды после завершения приёма).
- Реальная проблема — **утечка temp** (баг B-01): незавершённые/упавшие
  приёмы остаются в песочнице навсегда и продолжают числиться в «данных
  приложения», а «Очистить данные» в настройках Android удаляет их вместе с
  базой known_devices/shared caches. То есть страх «при удалении пропадут и
  переданные файлы» относится именно к упавшим передачам, застрявшим в
  temp, — успешно принятые файлы уже лежат в `Download/Landa` и удалению
  приложения не подлежат.

### Задачи

- [ ] **T-01 (HIGH). Гарантированный drain `incoming_temp`**
  - Закрыть B-01: любой исход передачи (success/fail/cancel/app kill при
    следующем старте) не оставляет файлов в песочнице.
  - KPI: после прогона сценариев fail/kill папка пуста.

- [ ] **T-02 (MEDIUM). Прямая запись в публичное хранилище минуя песочницу (Android 10+)**
  - Сегодня байты проходят двойную запись (temp → copy в MediaStore).
  - Вариант A (безопасный): писать потоково прямо в `MediaStore.Downloads`
    output-stream с первой секунды приёма, IS_PENDING=1, в конце атомарно
    публиковать. Убирает и двойной I/O, и сам класс temp-утечек.
  - Вариант B (fallback): оставить temp, но с T-01.
  - Выбрать вариант после прототипа A.

- [ ] **T-03 (MEDIUM). Прозрачность для пользователя**
  - Экран в настройках: сколько занимает кэш/temp, кнопка очистки,
    объяснение, что принятые файлы лежат в `Download/Landa` и переживают
    удаление приложения.

- [ ] **T-04 (LOW). Desktop-паритет**
  - Windows/Linux уже пишут мимо песочницы; проверить fallback-ветку
    `getApplicationDocumentsDirectory()` (когда `getDownloadsDirectory()`
    вернул null) — она должна быть помечена в UI как внутреннее хранилище.

---

## Правила ведения файла

- Закрытие задачи = `[x]` в этом же PR + ссылка на PR/коммит рядом с пунктом.
- Новые баги заносятся с evidence (`file:line`), без evidence — сначала в
  раздел расследования, потом в основной список.
- Замеры веса (S-01/S-02/S-03) фиксируются таблицей «было → стало» здесь же.
