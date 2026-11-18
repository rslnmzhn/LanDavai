# Отчёт об аудите качества и безопасности кодовой базы Landa

**Дата проведения:** 2026-09-12  
**Роль:** Senior QA & Security Engineer (Reasoning Builder / OwnBuilder)  
**Репозиторий:** LanDavai (`rslnmzhn/LanDavai.git`)  
**Ветка:** `main`

---

## Этап 0. Разведка и архитектурная карта

### 1. Стек технологий и окружение
- **Язык и фреймворк:** Dart 3.10.9 / Flutter 3.38.10 (Linux, Android, Windows, macOS, iOS).
- **Сетевое взаимодействие:** 
  - UDP (Broadcast / Unicast) на порт обнаружения и сигнализации LAN (`LanDiscoveryService`).
  - TCP сокеты для прямой передачи файлов (`FileTransferService`) и режима `NearbyTransfer`.
  - HTTP клиент (`HttpClient`) для проверки и скачивания обновлений с GitHub (`GithubReleaseUpdateService`, `AppUpdateDownloadService`).
- **Хранилище и СУБД:**
  - `sqflite` (Android/iOS) / `sqflite_common_ffi` (Linux/Windows) — база данных `landa.sqlite`.
  - Файловые кэши: JSON-индексы директорий (`.landa-cache.json`), превью миниатюр (`thumbnails/`).
- **Сериализация:**
  - JSON + base64url для UDP-дейтаграмм и пакетов протокола.
  - JSON + gzip для заголовков передачи файлов по TCP (`TransferHeaderCodec`).
- **CI/CD:**
  - GitHub Actions: `.github/workflows/build.yml` (задачи `quality`, `build-linux`, `build-windows`, `build-android`, `release`).
- **Тестовая инфраструктура:**
  - 125 файлов тестов в `test/` (модульные, интеграционные, регрессионные, архитектурные гарды `architecture_guard_test.dart`).

### 2. Точки входа
1. `lib/main.dart`: Инициализация Flutter, EasyLocalization, MediaKit, `SingleInstanceGuard`, запуск приложения.
2. `LanDiscoveryService` (UDP-сокет `0.0.0.0:0` / broadcast): Приём входящих пакетов протокола от других устройств LAN.
3. `FileTransferService` (TCP ServerSocket на динамическом порту): Приём входящих файлов по сети.
4. `LanNearbyTransportAdapter` (TCP ServerSocket/Socket): Приём сессий Nearby Transfer (в т.ч. через QR-код `landa-nearby://`).
5. `GithubReleaseUpdateService` (HTTPS REST API `api.github.com`): Проверка обновлений приложения.

### 3. Доверенные и недоверенные границы
| Граница | Уровень доверия | Источник данных | Потенциальные риски |
|---|---|---|---|
| UDP дейтаграммы LAN | **Недоверенный** | Любой хост в локальной сети / Wi-Fi | Спуфинг MAC/IP, DoS, Path Traversal, инъекции в парсеры, утечка данных |
| TCP сокет передачи файлов | **Недоверенный** | Подключившийся peer | Zip-бомбы, подмена файлов, Path Traversal, DoS |
| QR-коды Nearby Transfer | **Недоверенный** | Камера / сканер QR | Фальшивые URL/хосты, SSRF, подключение к произвольным IP |
| GitHub API / Releases | Полудоверенный | GitHub CDN / репозиторий | Path Traversal в имени файлов из манифеста, замена хэшей |
| Файловая система / Пути | Локальный | Пользовательские папки, имена файлов | Path Traversal (`../`), зарезервированные имена Windows, спецсимволы |
| База данных SQLite | Локальный | `landa.sqlite` | SQL Injection (используются параметризованные запросы `?`) |

---

## Этап 1. Статический анализ и поиск уязвимостей

### 1.1 Инъекции и Path Traversal
- **Критическая уязвимость:** `ThumbnailCacheService._resolveReceiverThumbnailFile` конкатенирует `cacheId` и `thumbnailId` через `p.join` без валидации на `..` или `/`. Удалённый злоумышленник по UDP может вызвать перезапись произвольных файлов (`.ssh/authorized_keys`, `.bashrc` и т.д.).
- **Высокая уязвимость:** `TransferPathPolicy.resolveReceiveRootPrefix` и `buildReceiveRelativePath` не блокируют `..` и абсолютные пути в параметре `destinationRelativeRootPrefix`, что позволяет файлам при передаче сохраняться вне каталога загрузок.
- **Средняя уязвимость:** `AppUpdateStorageService.createTargetFile` выполняет `p.join(directory.path, fileName)` без очистки через `p.basename(fileName)`.

### 1.2 Аутентификация, авторизация и спуфинг
- **Критическая уязвимость:** Аутентификация доверенных устройств («Друзей») опирается исключительно на поле `requesterMacAddress` в открытом UDP-пакете. Проверка `_isTrustedMac(normalizedRequesterMac)` не проверяет криптографическую подпись, хэндшейк или соответствие ARP-таблице.
  - Атакующий может слать UDP `LANDA_CLIPBOARD_QUERY_V1` с MAC-адресом известного друга и получать полный дамп системного буфера обмена жертвы (пароли, токены).
  - Атакующий может слать `LANDA_DOWNLOAD_REQUEST_V1` или `LANDA_SHARE_ACCESS_REQUEST_V1` с MAC друга и автоматически эксфильтровать общие файлы на свой TCP-порт без подтверждения жертвы.

### 1.3 Отказ в обслуживании (DoS) и ресурсоёмкие атаки
- **Высокая уязвимость:** `TransferHeaderCodec.decode` распаковывает gzip-заголовки через `gzip.decode(headerBytes)` без ограничения на размер распакованных данных в памяти (Decompression Bomb / Zip Bomb). Передача нескольких килобайт сжатых нулей приводит к OOM.
- **Высокая уязвимость:** `LanShareCatalogChunkReassembler` принимает `chunkCount` без ограничения (например, 1 000 000) и сохраняет промежуточные пакеты в Map, что приводит к исчерпанию памяти.
- **Средняя уязвимость:** `SocketExactReader` непрерывно аллоцирует поступающие байты в очередь `_chunks` без лимита на максимальный размер буфера.

### 1.4 Логические ошибки и надёжность
- **Средняя уязвимость:** `FileTransferService._receiveFiles` при получении валидного заголовка с пустым массивом `files: []` возвращает `success: true` («Received 0 files successfully»), даже если вызывающая сторона явно ожидала передачу конкретных файлов.
- **Низкая уязвимость:** В `SingleInstanceGuard` файл блокировки `landa_single_instance.lock` создаётся в общем `/tmp` без рандомизации UID пользователя, что на многопользовательских Linux-системах позволяет устроить локальный DoS или symlink-атаку.

---

## Этап 2 и 3. Классификация находок

| # | Файл / Модуль | Тип проблемы (CWE / OWASP) | Критичность | Как воспроизвести | Тест (Red Proof) |
|---|---|---|---|---|---|
| 1 | `lib/features/transfer/data/thumbnail_cache_service.dart` | **Path Traversal (CWE-22)**: Запись файлов по произвольным путям через `cacheId` / `thumbnailId` | **Critical** | Отправить `LANDA_THUMBNAIL_PACKET_V1` с `cacheId: "../../../../tmp"` | `test/security_adversarial_vulnerabilities_test.dart` ("saveReceiverThumbnailBytes rejects directory traversal") |
| 2 | `lib/features/discovery/application/clipboard_packet_route_adapter.dart`, `shared_download_boundary.dart` | **Authentication Bypass by Spoofing (CWE-290)**: Утечка буфера обмена и файлов при подмене MAC в UDP | **Critical** | Отправить `LANDA_CLIPBOARD_QUERY_V1` с `requesterMacAddress` доверенного друга с IP атакующего | `test/security_adversarial_vulnerabilities_test.dart` ("does not exfiltrate clipboard data to arbitrary IP spoofing a friend MAC") |
| 3 | `lib/features/transfer/application/transfer_path_policy.dart` | **Path Traversal (CWE-22)**: Выход за пределы директории загрузки через `destinationRelativeRootPrefix` | **High** | Передать `sharedLabel: ".."` или `destinationRelativeRootPrefix: "../../etc"` | `test/security_adversarial_vulnerabilities_test.dart` ("TransferPathPolicy rejects '..' and absolute paths") |
| 4 | `lib/features/transfer/data/transfer_header_codec.dart` | **Decompression Bomb / DoS (CWE-409, CWE-400)**: Неограниченная распаковка gzip в памяти | **High** | Отправить по TCP заголовок с 5 МБ сжатых нулей (~5 КБ в потоке) | `test/security_adversarial_vulnerabilities_test.dart` ("decode rejects decompression bombs exceeding safe size threshold") |
| 5 | `lib/features/discovery/data/lan_share_catalog_chunk_reassembler.dart` | **Uncontrolled Resource Consumption (CWE-400)**: Утечка памяти при аномальном `chunkCount` | **High** | Отправить `LanShareCatalogPacket` с `chunkCount = 1000000` | `test/security_adversarial_vulnerabilities_test.dart` ("LanShareCatalogChunkReassembler rejects excessive chunkCount") |
| 6 | `lib/app/update/data/app_update_storage_service.dart` | **Path Traversal (CWE-22)**: Создание файла обновления по относительному пути с `..` | **Medium** | Вызвать `createTargetFile('../../outside.bin')` | `test/security_adversarial_vulnerabilities_test.dart` ("createTargetFile sanitizes fileName against directory traversal") |
| 7 | `lib/features/transfer/data/file_transfer_service.dart` | **Improper Check for Exceptional Conditions (CWE-754)**: Ложный `success: true` при 0 переданных файлов | **Medium** | Подключиться к `startReceiver` и передать заголовок с `files: []` при ожидании файлов | `test/security_adversarial_vulnerabilities_test.dart` ("rejects transfer if expected items were specified but actual list is empty") |

---

## Этап 4. Результаты прогона тестов

1. **Adversarial Security Test Suite (`test/security_adversarial_vulnerabilities_test.dart`):**
   - Проверено тестов: **7**
   - **FAILING (RED): 7 из 7** (Каждый тест строго воспроизводит реальное уязвимое поведение кодовой базы).
2. **Happy Path & Regression Suite (`test/security_happy_path_test.dart`):**
   - Проверено тестов: **5**
   - **PASSING (GREEN): 5 из 5** (Легитимные сценарии работают корректно).
3. **Архитектурный контроль и базовые тесты (`architecture_guard_test.dart`, `smoke_test.dart`, `lan_packet_codec_test.dart`):**
   - **PASSING (GREEN)**.

---

## Этап 5. Расширенный полный аудит (Безопасность, Нативный слой, CI/CD и UI/UX) — 2026-11-18

### 5.1 Новые уязвимости безопасности и критические ошибки бэкенда / нативного слоя

| # | Файл / Модуль | Проблема (CWE) | Критичность | Детали и способ воспроизведения |
|---|---|---|---|---|
| 8 | `android/app/src/main/kotlin/com/example/landa/MainActivity.kt` (`copySharedUriToCache`), `res/xml/file_paths.xml` | **Confused Deputy / Arbitrary Private File Read (CWE-610, CWE-200) + FileUriExposedException Crash** | **Critical** | 1) Экспортированная `MainActivity` (`ACTION_SEND`) принимает `file://` URI или URI, ведущие внутрь приватного каталога приложения (`dataDir`/`filesDir`/`databases`), копируя `landa.sqlite` в `cacheDir/share_intent` для последующей отправки. 2) `file_paths.xml` содержит только `<external-path>`, из-за чего `installApkUpdate` падает с `FileUriExposedException` при установке APK из `files/Landa/updates`. 3) `buildDownloadsDocumentIntent` использует `startsWith(downloadsRoot)` без проверки границы слэша. |
| 9 | `lib/features/nearby_transfer/data/lan_nearby_transport_adapter.dart`, `nearby_transfer_session_store.dart` | **Authentication / Handshake Bypass & Unbounded Line DoS (CWE-287, CWE-400)** | **Critical** | 1) На стороне хоста `_sessionId` задан до подключения, а флаг `_handshakeCompleted` отсутствует; в `NearbyTransferSessionStore._onOfferReceived` получение `fileOffer` безусловно переводит фазу из `awaitingHandshake` в `connected`, полностью обходя ввод 2-значного кода подтверждения! 2) `LineSplitter()` на управляющем TCP-сокете не ограничивает длину строки без `\n` (OOM DoS). 3) `_handleFileReceiverReady` удаляет `offer` после первой выборки (нельзя докачать остальные файлы) и не ловит ошибки `sendFiles`/невалидный `port`. |
| 10 | `lib/features/transfer/application/remote_share_access_session_boundary.dart` | **MAC-Only Auto-Approval Spoofing (CWE-290)** | **High** | В отличие от `ClipboardPacketRouteAdapter` и `SharedDownloadBoundary`, `RemoteShareAccessSessionBoundary.handleRequestEvent` проверяет только MAC (`isTrustedSender(mac)` без сверки IP с `DeviceRegistry`), автоматически отправляя полный снимок расшаренных папок на произвольный `requesterIp:transferPort` при подмене MAC в UDP. |
| 11 | `lib/features/transfer/application/remote_share_access_snapshot_parser.dart` | **Decompression Bomb / Unbounded Gzip Decode (CWE-409, CWE-400)** | **High** | `gzip.decode(rawBytes)` вызывается без ограничения размера сжатого и распакованного снимка каталога, позволяя вызвать OOM при получении вредоносного `.gz`-снимка. |
| 12 | `lib/features/nearby_transfer/data/nearby_transfer_file_picker.dart`, `transfer_cache_preparation_path_resolver.dart` | **Symlink Following & Path Escape (CWE-59, CWE-22)** | **High** | `directory.list(recursive: true)` в `NearbyTransferFilePicker` следует символическим ссылкам (`followLinks: true` по умолчанию), позволяя раскрыть внешние файлы и зависнуть на циклических симлинках. В `TransferCachePreparationPathResolver` требуется защита от `..` в `entry.relativePath`. |
| 13 | `lib/features/transfer/data/video_link_share_service.dart` | **Unbounded POST Body DoS, Brute-Force & Weak Token Entropy (CWE-400, CWE-307, CWE-330)** | **High** | 1) `_readFormFields` читает весь POST-поток без лимита байт (OOM DoS на `/auth`). 2) Нет rate-limit на подбор пароля к `/auth`, сравнение токена/хэша не константно по времени, токен сессии использует `nextInt(1 << 31)` (31 бит энтропии вместо 256 бит), cookie без `SameSite=Lax`, `file.stat()` следует симлинкам. |
| 14 | `lib/features/nearby_transfer/data/qr_payload_codec.dart` | **SSRF / Unvalidated Host in QR Payload (CWE-918)** | **Medium** | `decodeLanFallbackConnection` принимает произвольные хосты (`127.0.0.1`, `169.254.169.254`, внешние домены/публичные IP) вместо валидных LAN/overlay IPv4-адресов. |
| 15 | `lib/app/update/data/github_release_update_service.dart`, `app_update_download_service.dart` | **Unbounded Download/Manifest Memory, Case-Sensitive SHA-256 & Scheme Check (CWE-400, CWE-319)** | **Medium** | 1) `AppUpdateDownloadService` загружает весь APK/архив в RAM через `readAsBytes()` для расчёта SHA-256 вместо потокового чтения и сравнивает хэш с учётом регистра. 2) `GithubReleaseUpdateService` не проверяет `https` у `manifestUrl`/ассетов и читает JSON без лимита размера. |
| 16 | `.github/workflows/build.yml`, `.github/appimage/AppImageBuilder.yml` | **CI Release Pipeline Failures (Linux AppImage)** | **Medium** | Падение `appimage-builder` на `packaging>=22` с Debian-версиями (`InvalidVersion: '1.21.1ubuntu2'`) и ошибка `Main executable is not an elf executable` из-за симлинка в `AppDir` (исправлено). |

---

### 5.2 Аудит интерфейса, вёрстки (Layout Shifts / Overflows), локализации и UX

Эмпирический прогон 12 экранов через `test/visual_ui_audit_harness_test.dart` (`320x680`, `360x680` с экранной клавиатурой, `640x360` landscape, `900x620` desktop) и построчный аудит выявили следующие дефекты:

1. **Реальные поломки вёрстки (`RenderFlex overflowed`) и наложения элементов:**
   - `DiscoveryDeviceListSection` (`discovery_device_list_section.dart:62–145, 740–795`):
     - Горизонтальный overflow **130 px** в `_IncomingTransferRequestTile` (строка с длинным именем файла и размером без `Expanded`/`ellipsis`).
     - Вертикальный overflow **12+ px** всего главного экрана (`Column`), так как карточки сводки сети, ошибок, входящих запросов и прогресса расположены фиксированно над `Expanded(child: ListView)`, сжимая список устройств в `0 px` на мобильных экранах и в landscape!
   - `RemoteDownloadBrowserPage` (`remote_download_browser_page.dart:278–420, 1284–1320`):
     - Горизонтальный overflow **82 px** в `_RemoteShareAccessActionRow` (длинный заголовок и кнопка «Запросить доступ» в одной строке без адаптивного переноса).
     - Катастрофический вертикальный overflow **1928 px** на экране «Скачать» на мобильных экранах/в плоском режиме и отсутствие подписки `AnimatedBuilder` на `remoteShareAccessSessionBoundary` (статус запроса доступа не перерисовывается!).
   - `NearbyTransferReceiveOfferSection` (`nearby_transfer_receive_offer_section.dart:119–206`):
     - **Наложение интерактивных элементов на 28 px по вертикали** в `_IncomingOfferTile`: `Positioned(top: 8, right: 8)` (`IconButton` 48×48) и `Positioned(bottom: 8, right: 8)` (`Checkbox` 48×48) в `Stack` высотой 84 px перекрывают друг друга.
     - Синхронный рендер всех элементов папки через `.map(...)` внутри `Column` без виртуализации и без `maxLines`/`ellipsis` у имён файлов.
   - `NearbyTransferDeviceListWidget` (`nearby_transfer_device_list_widget.dart:28–60`):
     - Горизонтальный overflow **19 px** заголовка `Row` без `Expanded` и неограниченная ширина `ChoiceChip`.
   - `NearbyTransferQrView` и `NearbyTransferScannerView` (`nearby_transfer_qr_view.dart`, `nearby_transfer_scanner_view.dart`):
     - Фиксированный стейдж `280×280` и пульсирующие кольца (`317 px`) выходят за пределы узких и альбомных экранов; у `QrImageView` стоит дефолтный `QrErrorCorrectLevel.L` (~7%) при перекрытии центра логотипом `42×42` (высокий риск нечитаемости QR).
     - В `NearbyTransferScannerView` внутри `SingleChildScrollView` `constraints.biggest.shortestSide` игнорирует высоту экрана (`maxHeight = Infinity`), раздувая сканер в landscape; тикер анимации крутится вхолостую на Desktop; у `MobileScanner` отсутствует `errorBuilder`.
   - `ShareTargetPage` (`share_target_page.dart:69–74`):
     - Горизонтальный overflow **6.5 px** кнопки `TextButton` в `AppBar.actions` на экране `320 px`.
   - `NearbyTransferConnectionConfirmView` (`nearby_transfer_connection_confirm_view.dart`):
     - Отсутствует учёт `MediaQuery.viewInsetsOf(context).bottom` при открытии клавиатуры в bottom sheet.

2. **Отвратительные UX-сценарии и тупики (Dead-Ends):**
   - **Скрытое меню действий устройства (`_DeviceTile` в `discovery_device_list_section.dart:880–950`)**: переименование и добавление в друзья спрятаны за неочевидный жест (долгое нажатие на телефоне / правый клик на ПК) без видимой кнопки `⋮` (`Icons.more_vert_rounded`).
   - **Удаление из друзей в один случайный клик (`discovery_friends_sheet.dart:95–108`)**: деструктивное удаление доверенного пира выполняется мгновенно без диалога подтверждения (нарушение `AGENTS.md`: *"Critical actions require explicit confirmation"*).
   - **Неудобный экран настроек (`AppSettingsSheet` / `app_settings_tab_sections.dart`)**:
     - На десктопах рендерится абсолютно пустая карточка `settings.interface_title` когда скрыты мобильные/системные переключатели;
     - 5 числовых полей на вкладке «Хранилище и логи» требуют нажимать отдельную кнопку «Сохранить» у каждого поля без индикации несохранённых изменений и без сохранения по `onSubmitted`, при закрытии введённые значения молча теряются.
   - **Тупики в `NearbyTransfer`**:
     - Вечный `CircularProgressIndicator` без кнопки повтора при отсутствии локального IP на старте отправки;
     - «Мёртвый» QR-код на закрытом сокете после истечения 30-секундного кода или ошибки рукопожатия (`_activeAdapter.disconnect()` закрывает `ServerSocket`, но оставляет старый `_qrPayloadText` на экране);
     - Полный тупик на Desktop без камеры, если список устройств пуст или порт нестандартный (нет поля вставки кода сессии / ручного подключения, а у отправителя нельзя скопировать код сессии);
     - Ложная зелёная галочка успеха при сканировании любого постороннего QR-кода;
     - Слепая фаза `connecting` (до 10 сек без спиннера и кнопки отмены);
     - На экране подтверждения 2-значного кода не видно имя/IP подключающегося устройства и оставшиеся секунды таймера;
     - Не заблокированы кнопки «Выбрать файлы» и «Скачать выбранные» во время активной передачи, нет процентов/байт прогресса, а после скачивания список файлов и пути сохранения пропадают без возможности открыть папку или докачать оставшиеся файлы;
     - Стартовый `ModalBottomSheet` выбора режима нельзя закрыть свайпом/тапом по фону (`isDismissible: false`), а кнопка «Назад» в sheet-режиме рвёт активное соединение без подтверждения.

3. **Дизайн-система, шрифты и локализация (`AGENTS.md` Guardrails):**
   - Шрифты `Manrope` и `JetBrains Mono` использовались в `AppTypography`, но отсутствовали в `pubspec.yaml` / `assets/fonts/`, а в 2 виджетах была опечатка `'JetBrainsMono'` без пробела; в `AppTypography` не определены `titleSmall` и `labelLarge`, вызываемые в десятке виджетов; кнопки не выдерживают контракт высоты `44` mobile / `40` desktop; в `qr_view.dart`, `scanner_view.dart`, `clipboard_sheet_list.dart` использованы сырые `Colors.*` / `Color(0x...)`.
   - Более 30 захардкоженных русских и английских строк в `NearbyTransferSessionStore`, `LanNearbyTransportAdapter`, `NearbyTransferFilePicker`, `RemoteShareAccessSessionBoundary`, `DebugLogAccessService` и `DiscoveryDeviceListSection` (`MAC ...`, `OS ...`) выводятся напрямую в UI мимо `easy_localization` (при этом `easy_localization` должен оставаться строго в `presentation/`).

---

## Этап 6. План исправления (5 фаз)

1. **Фаза 1 — Безопасность, сетевой транспорт и нативный Android-слой:**
   - Ввести строгий флаг завершённого рукопожатия в `LanNearbyTransportAdapter` и проверку фазы в `NearbyTransferSessionStore`, ограничить длину строки в TCP control-канале (`64 КБ`), сохранять исходящий `offer` для повторной докачки файлов и обернуть `sendFiles` в `try/catch` с проверкой порта `1..65535`.
   - Перевести `RemoteShareAccessSessionBoundary` на комбинированную проверку `isTrustedSender(ip, mac)`.
   - Заменить `gzip.decode` в `RemoteShareAccessSnapshotParser` на потоковую распаковку с лимитом `maxDecompressedBytes` (32 МБ).
   - Укрепить `VideoLinkShareService` (лимит POST-тела 8 КБ, защита от brute-force по IP, 256-битный токен, константное по времени сравнение, `SameSite=Lax`, запрет симлинков).
   - Отключить следование симлинкам в `NearbyTransferFilePicker` (`followLinks: false`), защитить `TransferCachePreparationPathResolver` от `..`, валидировать LAN/overlay IPv4 в `NearbyTransferQrCodec.decodeLanFallbackConnection`, перевести `AppUpdateDownloadService` на потоковый SHA-256 без учёта регистра и проверку `https` в `GithubReleaseUpdateService`.
   - Исправить `MainActivity.kt` (принимать только внешние `content://` URI вне приватных директорий Landa, исправить проверку префикса `downloadsRoot`, убрать аварийный `Uri.fromFile` fallback) и добавить `<files-path>` / `<cache-path>` в `android/app/src/main/res/xml/file_paths.xml`.
   - Покрыть все новые векторы тестами в `test/security_adversarial_vulnerabilities_test.dart`.
2. **Фаза 2 — Дизайн-система, шрифты и локализация:**
   - Подключить `Manrope` и `JetBrains Mono` в `pubspec.yaml`, добавить `titleSmall` и `labelLarge` в `AppTypography`, задать высоты кнопок `44` (mobile) / `40` (desktop) и семантические токены в `AppTheme`/`AppColors`, убрать `Colors.*` и `'JetBrainsMono'`.
   - Заменить строковый хардкод в `NearbyTransferSessionStore`, `LanNearbyTransportAdapter`, `DebugLogAccessService` и границах на типизированные коды/параметры с локализацией строго в `presentation/` через `assets/translations/ru.json` и `en.json`.
3. **Фаза 3 — Вёрстка и UX основных экранов (Discovery, Remote Download, Settings, Friends, Files, ShareTarget):**
   - Перевести `DiscoveryDeviceListSection` на единый `CustomScrollView` (устранив вертикальный overflow), исправить вёрстку карточек входящих запросов и добавить видимую кнопку меню `⋮` на `_DeviceTile`.
   - В `RemoteDownloadBrowserPage` устранить вертикальный и горизонтальный overflow, подписать экран на `remoteShareAccessSessionBoundary`.
   - Добавить диалог подтверждения при удалении друга в `DiscoveryFriendsSheet`, исправить `AppBar` в `ShareTargetPage`, скрыть пустую карточку интерфейса и улучшить сохранение настроек в `AppSettingsSheet`.
4. **Фаза 4 — Вёрстка и UX `NearbyTransfer`:**
   - Перестроить `_IncomingOfferTile` с `Stack`/`Positioned` на чистый адаптивный `Row` без наложений, виртуализировать список узлов, добавить сводку выбранного, прогресс в байтах/процентах, карточку завершённого приёма с открытием папки и возможность докачать оставшиеся файлы.
   - Поставить `QrErrorCorrectLevel.H`, адаптировать размер QR и сканера к landscape/узким экранам, остановить холостой тикер на Desktop, добавить копирование кода подключения у отправителя и поле ручного подключения по коду/QR-строке у получателя (решив тупик на ПК без камеры), автоматически переоткрывать хостинг/QR после истечения кода и показывать состояние при отсутствии IP.
5. **Фаза 5 — Сквозная проверка:**
   - Добиться `AUDIT_FINDINGS_COUNT=0` в `test/visual_ui_audit_harness_test.dart` на всех 12 экранах и форм-факторах, `0` предупреждений `flutter analyze`, зелёного прогона всех тестов (включая `architecture_guard_test.dart` и `god_service_regression_guard_test.dart`) и провести финальный аудит независимым верификатором.
