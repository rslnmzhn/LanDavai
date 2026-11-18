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
