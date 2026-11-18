# Roadmap проекта Landa

## Аудит безопасности и качества — 2026-09-12

### Critical
- [x] **Уязвимость Path Traversal при сохранении миниатюр (превью) удалённых папок**, файл: `lib/features/transfer/data/thumbnail_cache_service.dart`, тест: `test/security_adversarial_vulnerabilities_test.dart` ("ThumbnailCacheService.saveReceiverThumbnailBytes rejects directory traversal in cacheId and thumbnailId").
  - *Реализованный фикс:* Внедрён санитайзинг токенов `_sanitizeToken` (только `[a-zA-Z0-9_-]`), исключающий `..` и `/` из путей сохранения миниатюр.
- [x] **Небезопасная аутентификация доверенных устройств («Друзей») по незащищённому MAC в UDP-пакетах**, файл: `lib/features/discovery/application/clipboard_packet_route_adapter.dart`, `lib/features/transfer/application/shared_download_request_mapper.dart`, `lib/features/discovery/application/discovery_controller.dart`, `lib/app/discovery/discovery_composition.dart`, тест: `test/security_adversarial_vulnerabilities_test.dart` ("ClipboardPacketRouteAdapter does not exfiltrate clipboard data to arbitrary IP spoofing a friend MAC").
  - *Реализованный фикс:* Добавлена проверка `isTrustedSender` / `isTrustedSenderIpAndMac`, сверяющая IP отправителя с фактической привязкой MAC-адреса устройства в `DeviceRegistry`, предотвращая тихую эксфильтрацию данных по поддельным UDP-дейтаграммам.

### High
- [x] **Уязвимость Path Traversal в TransferPathPolicy при формировании префикса принимаемых файлов**, файл: `lib/features/transfer/application/transfer_path_policy.dart`, тест: `test/security_adversarial_vulnerabilities_test.dart` ("TransferPathPolicy rejects \"..\" and absolute paths in destinationRelativeRootPrefix").
  - *Реализованный фикс:* В `resolveReceiveRootPrefix` заблокированы последовательности `..`, `.` и пустые префиксы; в `buildReceiveRelativePath` префикс принудительно санируется через `sanitizeRelativePath`, исключая выход за пределы директории загрузок.
- [x] **Уязвимость Decompression Bomb (Zip Bomb) в TransferHeaderCodec при приёме заголовков передачи**, файл: `lib/features/transfer/data/transfer_header_codec.dart`, тест: `test/security_adversarial_vulnerabilities_test.dart` ("TransferHeaderCodec.decode rejects decompression bombs exceeding safe size threshold").
  - *Реализованный фикс:* Реализован `_BoundedByteSink` с лимитом `maxDecompressedBytes = 2 МБ`, выбрасывающий `FormatException` при превышении лимита распакованных данных.
- [x] **Отсутствие лимита на `chunkCount` в LanShareCatalogChunkReassembler**, файл: `lib/features/discovery/data/lan_share_catalog_chunk_reassembler.dart`, тест: `test/security_adversarial_vulnerabilities_test.dart` ("LanShareCatalogChunkReassembler rejects excessive chunkCount to prevent memory exhaustion").
  - *Реализованный фикс:* Добавлены лимиты `maxChunkCount = 128` и `maxPendingReassemblies = 256`, отсекающие DoS-пакеты с аномальным числом фрагментов.

### Medium / Low
- [x] **Path Traversal в AppUpdateStorageService.createTargetFile**, файл: `lib/app/update/data/app_update_storage_service.dart`, тест: `test/security_adversarial_vulnerabilities_test.dart` ("AppUpdateStorageService.createTargetFile sanitizes fileName against directory traversal").
  - *Реализованный фикс:* Применено извлечение чистого имени файла через `p.basename(fileName.trim())`.
- [x] **Ложный флаг `success: true` в FileTransferService при приёме 0 файлов**, файл: `lib/features/transfer/data/file_transfer_service.dart`, тест: `test/security_adversarial_vulnerabilities_test.dart` ("FileTransferService._receiveFiles rejects transfer if expected items were specified but actual list is empty").
  - *Реализованный фикс:* Добавлено условие генерации ошибки при пустом фактическом манифесте `normalizedActual.isEmpty`, когда ожидались файлы.
- [x] **Использование предсказуемого пути `/tmp/landa_single_instance.lock` в SingleInstanceGuard**, файл: `lib/core/utils/single_instance_guard.dart`.
  - *Реализованный фикс:* Изоляция директории блокировки в `XDG_RUNTIME_DIR` на Linux либо в отдельный подкаталог с именем пользователя `landa_$user`.

### Технический долг / улучшения покрытия тестами
- [ ] Добавить интеграционное тестирование с проверкой граничных значений для TCP `SocketExactReader` на устойчивость к незавершённым потокам и переполнению буфера.
- [ ] Расширить fuzzing-тесты парсера входящих UDP датаграмм `LanIncomingDatagramAdmission` на предмет битого UTF-8, сверхдлинных строк и неожиданных управляющих символов.
- [ ] Включить в CI автоматическую проверку на отсутствие утечек путей (path traversal) при любых операциях распаковки и сохранения кэша.

### Задачи, требующие ручного тестирования пользователем
- [ ] **E2E сквозное тестирование между физическими устройствами в реальной Wi-Fi сети:**
  - Проверка обнаружения устройств на реальных мобильных телефонах (Android/iOS) и десктопах (Windows/Linux).
  - Сканирование QR-кодов в `NearbyTransfer` через физическую камеру устройства.
  - Проверка корректности записи файлов через Android Storage Access Framework (SAF) на реальных версиях Android 11–14.

---

## Расширенный аудит безопасности, стабильности и UI/UX — 2026-11-18

### Фаза 1: Безопасность, протоколы и нативный Android-слой
- [x] **Android Confused Deputy (`ACTION_SEND` `file://` / приватные пути) и `FileProvider` для самообновления APK**, файлы: `android/app/src/main/kotlin/com/example/landa/MainActivity.kt`, `android/app/src/main/res/xml/file_paths.xml`.
- [x] **Обход 2-значного рукопожатия и OOM в управляющем TCP-канале Nearby Transfer**, файлы: `lib/features/nearby_transfer/data/lan_nearby_transport_adapter.dart`, `lib/features/nearby_transfer/application/nearby_transfer_session_store.dart`.
- [x] **Автоматическое одобрение доступа к шарам по поддельному MAC без сверки IP**, файлы: `lib/features/transfer/application/remote_share_access_session_boundary.dart`, `lib/features/transfer/application/remote_share_access_session_models.dart`, `lib/features/transfer/application/transfer_session_coordinator.dart`.
- [x] **Защита от Gzip-бомбы в `RemoteShareAccessSnapshotParser`**, файл: `lib/features/transfer/application/remote_share_access_snapshot_parser.dart`.
- [x] **Защита `VideoLinkShareService` (лимит тела POST, защита от перебора пароля, 256-битный токен, constant-time сравнение, запрет симлинков)**, файл: `lib/features/transfer/data/video_link_share_service.dart`.
- [x] **Запрет следования симлинкам в `NearbyTransferFilePicker`, защита путей в `TransferCachePreparationPathResolver`, валидация LAN IP в QR и потоковый SHA-256 в `AppUpdateDownloadService` / HTTPS в `GithubReleaseUpdateService`**.

### Фаза 2: Дизайн-система, шрифты и локализация
- [x] **Подключение шрифтов `Manrope` и `JetBrains Mono` в `pubspec.yaml`, выравнивание `AppTypography` (`titleSmall`, `labelLarge`), высот кнопок (`44`/`40`) и цветовых токенов**.
- [x] **Вынос 30+ захардкоженных строк из `NearbyTransferSessionStore`, `LanNearbyTransportAdapter`, `DebugLogAccessService` и виджетов в `assets/translations/ru.json` и `en.json` с сохранением границы локализации в `presentation/`**.

### Фаза 3: Исправление вёрстки и UX основных экранов
- [x] **Устранение горизонтального и вертикального `RenderFlex overflow` в `DiscoveryDeviceListSection` (переход на единый скролл `CustomScrollView`) + видимая кнопка меню `⋮` на карточках устройств**.
- [x] **Устранение `RenderFlex overflow` и починка реактивности статуса доступа в `RemoteDownloadBrowserPage`**.
- [x] **Подтверждение удаления из друзей в `DiscoveryFriendsSheet`, исправление `AppBar` в `ShareTargetPage`, скрытие пустой секции и улучшение сохранения настроек в `AppSettingsSheet`**.

### Фаза 4: Исправление вёрстки и UX `NearbyTransfer`
- [x] **Устранение 28px наложения кнопок в `_IncomingOfferTile`, виртуализация списка файлов, отображение прогресса (проценты/объём), карточки полученных файлов с открытием папки и повторной докачки из того же предложения**.
- [x] **`QrErrorCorrectLevel.H`, адаптивный размер QR/сканера в landscape и на узких экранах, копирование кода сессии и ручное подключение на Desktop без камеры, обработка отсутствия локального IP**.
