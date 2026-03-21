
# Refactor Master Plan

## 1. Title and Scope

Этот документ фиксирует план поэтапного архитектурного рефактора для Dart-слоя проекта Landa. Это не документ реализации и не место для целевого кода. Здесь зафиксированы текущие architectural failures, целевая ownership model, migration mechanics, compatibility rules, test gates и deletion criteria.

Охват аудита:
- `lib/`
- `test/`

Вне охвата:
- `android/`
- `ios/`
- `linux/`
- `macos/`
- `windows/`
- `web/`
- platform-specific реализации за method channel boundary, если они не видны из Dart-кода

Evidence level: Confirmed from code  
Source of truth: `lib/`, `test/`, `lib/core/storage/app_database.dart` / `AppDatabase`, `lib/features/discovery/application/discovery_controller.dart` / `DiscoveryController`

Missing artifact:
- Реальные native-side transport/storage integrations, если часть поведения скрыта за platform APIs.

Impact of uncertainty:
- Нельзя честно подтвердить часть runtime guarantees по network stack, filesystem semantics и background execution только на основе Dart-слоя.

Safest interim assumption:
- План миграции должен сохранять существующие Dart-visible contracts до тех пор, пока platform-specific flows не будут отдельно проверены.

## 2. Executive Summary

Архитектура проекта уже структурно небезопасна для локальных изменений. Один change в зоне discovery/files/transfer цепляет state ownership, persistence, transport, UI lifecycle и side effects одновременно. Это не “несколько крупных файлов”. Это отсутствие устойчивых границ власти над состоянием.

Наиболее токсичные зоны:
- `lib/features/discovery/application/discovery_controller.dart` / `DiscoveryController`
- `lib/features/discovery/presentation/discovery_page.dart` / `DiscoveryPage`
- `lib/features/discovery/data/lan_discovery_service.dart` / `LanDiscoveryService`
- `lib/features/transfer/data/shared_folder_cache_repository.dart` / `SharedFolderCacheRepository`
- `lib/features/files/presentation/file_explorer_page.dart` и `lib/features/files/presentation/file_explorer/*`

Incremental refactor ещё реален. Rewrite пока не обязателен, потому что текущие persistence anchors и protocol anchors видны из Dart-кода и могут быть удержаны как compatibility boundary:
- `known_devices`
- `shared_folder_caches`
- `transfer_history`
- `app_settings`
- `friends`
- `clipboard_history`
- packet identifiers в `LanDiscoveryService`

Локальные изменения уже опасны, потому что реальный owner состояния не совпадает с declared role классов:
- `DiscoveryController` заявлен как controller, но по факту владеет и state, и orchestration, и side effects.
- `DiscoveryPage` заявлена как UI screen, но по факту собирает dependency graph и запускает feature flows.
- `LanDiscoveryService` заявлен как discovery service, но по факту держит transport/protocol/codecs/scenario dispatch.
- `SharedFolderCacheRepository` заявлен как repository, но по факту совмещает persistence, indexing и cache lifecycle.

Evidence level: Confirmed from code  
Source of truth: `lib/features/discovery/application/discovery_controller.dart` / `DiscoveryController`, `_devicesByIp`, `_ownerSharedCaches`, `_trustedDeviceMacs`, `_clipboardHistory`; `lib/features/discovery/presentation/discovery_page.dart` / `DiscoveryPage`, `AppDatabase.instance`, `DiscoveryController(...)`; `lib/features/discovery/data/lan_discovery_service.dart` / `LanDiscoveryService`, `LANDA_DISCOVER_V1`, `sendTransferRequest`, `_decodeTransferEnvelope`; `lib/features/transfer/data/shared_folder_cache_repository.dart` / `SharedFolderCacheRepository`, `upsertOwnerFolderCache`, `buildOwnerSelectionCache`, `_indexFolder`

## 3. Current Architecture Breakdown

### 3.1 Discovery

Главные классы:
- `lib/features/discovery/application/discovery_controller.dart` / `DiscoveryController`
- `lib/features/discovery/data/lan_discovery_service.dart` / `LanDiscoveryService`
- `lib/features/discovery/data/device_alias_repository.dart` / `DeviceAliasRepository`
- `lib/features/discovery/data/friend_repository.dart` / `FriendRepository`
- `lib/features/discovery/domain/discovered_device.dart` / `DiscoveredDevice`

Фактический owner состояния:
- `DiscoveryController` держит `_devicesByIp`, `_aliasByMac`, `_trustedDeviceMacs`, `_friends`, `_clipboardHistory`, `_ownerSharedCaches`, `_ownerIndexEntriesByCacheId`, `_downloadHistory`, `_remoteShareOptions`.

Где ownership размыт:
- Device reachability живёт по IP в `_devicesByIp`, а alias/trust живут по MAC через `DeviceAliasRepository`.
- Internet peers и local peer identity частично живут в `FriendRepository`, хотя persistence у них проходит через `app_settings` и `friends`.

Какие side effects смешаны со state:
- network event handling
- share catalog handling
- clipboard query handling
- transfer request/decision handling
- settings load/save
- cache load/refresh

Где нарушены layer boundaries:
- controller напрямую знает о network service, repositories, storage, UI-facing projections и notification-like effects.

Evidence level: Confirmed from code  
Source of truth: `lib/features/discovery/application/discovery_controller.dart` / `_devicesByIp`, `_trustedDeviceMacs`, `_clipboardHistory`, `_ownerSharedCaches`, `_loadSettings`, `_saveSettings`, `_handleClipboardQuery`, `_handleShareCatalog`, `_onTransferRequest`, `_onTransferDecision`

### 3.2 Files

Главные классы:
- `lib/features/files/presentation/file_explorer_page.dart`
- `lib/features/files/presentation/file_explorer/file_explorer_page_state.dart` / `FileExplorerPage`
- `lib/features/files/presentation/file_explorer/local_file_viewer.dart` / `LocalFileViewerPage`
- `lib/features/files/presentation/file_explorer/media_preview_cache.dart` / `_MediaPreviewCache`

Фактический owner состояния:
- files feature не имеет чистого отдельного owner. Ownership размазан между `part`-based presentation module, controller callbacks из discovery и static preview cache.

Где ownership размыт:
- navigation/search/sort/view state и preview/media concerns находятся в общем `part` namespace.
- file explorer открывается из `DiscoveryPage`, а данные и callbacks приходят из discovery слоя.

Какие side effects смешаны со state:
- preview generation
- recache status UI
- local viewer behavior

Где нарушены layer boundaries:
- presentation module является фактическим feature boundary и одновременно runtime state holder, потому что отдельный application owner отсутствует.

Evidence level: Confirmed from code  
Source of truth: `lib/features/files/presentation/file_explorer_page.dart` / `part 'file_explorer/file_explorer_page_state.dart'`, `part 'file_explorer/media_preview_cache.dart'`, `part 'file_explorer/local_file_viewer.dart'`; `lib/features/discovery/presentation/discovery_page.dart` / `_openFileExplorer`

### 3.3 Transfers

Главные классы:
- `lib/features/transfer/data/file_transfer_service.dart` / `FileTransferService`
- `lib/features/transfer/data/transfer_storage_service.dart` / `TransferStorageService`
- `lib/features/transfer/data/video_link_share_service.dart` / `VideoLinkShareService`

Фактический owner состояния:
- transfer/session ownership не изолирован. Runtime decisions проходят через discovery-driven flows, while file IO and video share flows живут в отдельных service classes.

Где ownership размыт:
- send/receive orchestration распределена между `DiscoveryController`, `LanDiscoveryService`, `FileTransferService`, `TransferStorageService`.
- `VideoLinkShareService` держит `activeSession`, но lifecycle открытия/остановки зависит от внешней orchestration.

Какие side effects смешаны со state:
- TCP receiving/sending
- filesystem publishing
- preview cleanup
- ad-hoc local HTTP serving for video watch flow

Где нарушены layer boundaries:
- application orchestration не отделена от infra services.

Evidence level: Confirmed from code  
Source of truth: `lib/features/transfer/data/file_transfer_service.dart` / `startReceiver`, `sendFiles`, `_receiveFiles`; `lib/features/transfer/data/transfer_storage_service.dart` / `resolveReceiveDirectory`, `cleanupPreviewCache`, `publishToUserDownloads`; `lib/features/transfer/data/video_link_share_service.dart` / `activeSession`, `publish`, `stop`

### 3.4 Clipboard / History

Главные классы:
- `lib/features/clipboard/data/clipboard_history_repository.dart` / `ClipboardHistoryRepository`
- `lib/features/clipboard/data/clipboard_capture_service.dart` / `ClipboardCaptureService`
- `lib/features/clipboard/presentation/clipboard_sheet.dart` / `ClipboardSheet`
- `lib/features/discovery/application/discovery_controller.dart` / `DiscoveryController`

Фактический owner состояния:
- persisted history живёт в `ClipboardHistoryRepository`, но UI и feature access идут через `DiscoveryController.clipboardHistory` и remote clipboard projections inside discovery runtime state.

Где ownership размыт:
- local history, dedupe state и remote clipboard entries распределены между repository, capture service и controller.

Какие side effects смешаны со state:
- clipboard polling/capture
- remote clipboard query handling
- UI-selected remote source state

Где нарушены layer boundaries:
- `ClipboardSheet` зависит от `DiscoveryController` напрямую вместо отдельного feature owner.

Evidence level: Confirmed from code  
Source of truth: `lib/features/clipboard/presentation/clipboard_sheet.dart` / `final DiscoveryController controller`, `widget.controller.clipboardHistory`, `widget.controller.remoteClipboardEntriesFor`; `lib/features/discovery/application/discovery_controller.dart` / `_clipboardHistory`, `_handleClipboardQuery`, `_onClipboardCatalog`; `lib/features/clipboard/data/clipboard_history_repository.dart` / `listRecent`, `insert`, `trimToMaxEntries`

### 3.5 Settings / Identity

Главные классы:
- `lib/features/settings/data/app_settings_repository.dart` / `AppSettingsRepository`
- `lib/features/discovery/data/friend_repository.dart` / `FriendRepository`
- `lib/features/discovery/data/device_alias_repository.dart` / `DeviceAliasRepository`

Фактический owner состояния:
- settings values живут в `app_settings`, local peer identity тоже частично живёт там через `FriendRepository._localPeerIdKey`, а device alias/trust живут в `known_devices`.

Где ownership размыт:
- `FriendRepository` управляет `local_peer_id`, хотя это не friend relation.
- alias/trust model anchored on MAC conflicts with runtime peer/session model anchored on IP.

Какие side effects смешаны со state:
- load-or-create identity
- trust mutation
- seen-device recording

Где нарушены layer boundaries:
- one repository mutates settings-owned key for a discovery-specific concept.

Evidence level: Confirmed from code  
Source of truth: `lib/features/discovery/data/friend_repository.dart` / `_localPeerIdKey`, `loadOrCreateLocalPeerId`; `lib/features/settings/data/app_settings_repository.dart` / `load`, `save`; `lib/features/discovery/data/device_alias_repository.dart` / `recordSeenDevices`, `loadTrustedMacs`, `setTrusted`

### 3.6 Shared Cache

Главные классы:
- `lib/features/transfer/data/shared_folder_cache_repository.dart` / `SharedFolderCacheRepository`
- `lib/features/transfer/domain/shared_folder_cache.dart` / `SharedFolderCache`
- `lib/features/discovery/application/discovery_controller.dart` / `DiscoveryController`

Фактический owner состояния:
- durable metadata живёт в `shared_folder_caches`.
- index contents живут в JSON files.
- read projections и mirrors живут в `DiscoveryController`.

Где ownership размыт:
- repository строит и пишет cache artifacts, controller кэширует и подмешивает их в feature runtime state, files UI строит собственные projections.

Какие side effects смешаны со state:
- indexing filesystem
- rebinding caches to MAC
- pruning unavailable caches
- selection cache generation

Где нарушены layer boundaries:
- repository выполняет orchestration и policy, а controller держит mirrors поверх repository state.

Evidence level: Confirmed from code  
Source of truth: `lib/features/transfer/data/shared_folder_cache_repository.dart` / `upsertOwnerFolderCache`, `buildOwnerSelectionCache`, `saveReceiverCache`, `readIndexEntries`, `pruneUnavailableOwnerCaches`, `rebindOwnerCachesToMac`, `_indexFolder`; `lib/features/discovery/application/discovery_controller.dart` / `_ownerSharedCaches`, `_ownerIndexEntriesByCacheId`, `_loadOwnerCaches`

### 3.7 Protocol / Transport

Главные классы:
- `lib/features/discovery/data/lan_discovery_service.dart` / `LanDiscoveryService`
- `lib/features/transfer/data/file_transfer_service.dart` / `FileTransferService`

Фактический owner состояния:
- protocol/session state partially hidden inside `LanDiscoveryService` plus controller event handlers.

Где ownership размыт:
- packet constants, UDP socket lifecycle, packet encoding/decoding and scenario-specific send methods coexist in one class.
- transfer session decisions start in discovery protocol and continue in separate transfer services.

Какие side effects смешаны со state:
- UDP start/stop
- packet send/receive
- envelope decode
- share/clipboard/friend/transfer packet dispatch

Где нарушены layer boundaries:
- infra service decides scenario shape instead of exposing low-level transport and codecs to application layer.

Evidence level: Confirmed from code  
Source of truth: `lib/features/discovery/data/lan_discovery_service.dart` / `LANDA_DISCOVER_V1`, `LANDA_TRANSFER_REQUEST_V1`, `start`, `sendTransferRequest`, `sendTransferDecision`, `sendShareCatalog`, `sendClipboardCatalog`, `_decodeTransferEnvelope`

## 4. God-Class and God-Module Audit

### 4.1 `DiscoveryController`

- Declared role:
  - ChangeNotifier controller for discovery screen and adjacent flows.
- Actual role:
  - Runtime state monopoly, orchestration hub, persistence bridge, network event sink, UI read-model assembler.
- Owned state:
  - `_devicesByIp`
  - `_aliasByMac`
  - `_trustedDeviceMacs`
  - `_friends`
  - `_clipboardHistory`
  - `_ownerSharedCaches`
  - `_ownerIndexEntriesByCacheId`
  - `_downloadHistory`
  - `_remoteShareOptions`
- Illegal responsibilities:
  - network protocol reaction
  - transfer decision handling
  - clipboard handling
  - settings load/save
  - shared cache loading
  - local device MAC resolution
  - feature read-model assembly
- External dependencies:
  - repositories for alias/friend/settings/history/cache
  - discovery service
  - transfer services
  - file/video/preview related collaborators
- Why local refactor is unsafe:
  - любое изменение в одном сценарии рискует сломать unrelated runtime state, потому что общий owner и общий notification cycle уже сцеплены.
- Target decomposition:
  - `DeviceRegistry`
    - Legacy owner unloaded: `DiscoveryController`
    - State seam closed: device reachability and identity mapping
    - Justifying migration phase: Phase 3 after vocabulary and identity split
  - `TrustedLanPeerStore`
    - Legacy owner unloaded: `DiscoveryController`
    - State seam closed: trust ownership separate from internet peer list
    - Justifying migration phase: Phase 3
  - `ClipboardHistoryStore`
    - Legacy owner unloaded: `DiscoveryController`
    - State seam closed: local clipboard durable state vs remote clipboard projection
    - Justifying migration phase: Phase 6
  - `SharedCacheCatalog`
    - Legacy owner unloaded: `DiscoveryController`
    - State seam closed: shared cache catalog and index projection
    - Justifying migration phase: Phase 5
  - `Discovery read/application model`
    - Legacy owner unloaded: `DiscoveryController`
    - State seam closed: UI-facing discovery projection without owning durable truth
    - Justifying migration phase: Phase 3
- Migration difficulty:
  - High. The class is both read path and write path for multiple domains.
- Deletion criteria:
  - class no longer owns durable or session truth outside discovery-specific read-model assembly
  - all write paths moved to explicit target owners
  - remaining logic reduced to thin projection or removed entirely
- Evidence level:
  - Confirmed from code
- Source of truth:
  - `lib/features/discovery/application/discovery_controller.dart` / `DiscoveryController`, `_devicesByIp`, `_ownerSharedCaches`, `_trustedDeviceMacs`, `_clipboardHistory`, `_loadSettings`, `_saveSettings`, `_onTransferRequest`, `_handleClipboardQuery`

### 4.2 `DiscoveryPage`

- Declared role:
  - screen widget for discovery feature
- Actual role:
  - UI-hosted composition root and flow coordinator
- Owned state:
  - widget lifecycle state, plus indirectly created graph through `AppDatabase.instance` and `DiscoveryController(...)`
- Illegal responsibilities:
  - dependency assembly
  - feature launching for friends/clipboard/settings/files/history
  - lifecycle ownership of cross-feature dependencies
- External dependencies:
  - `AppDatabase`
  - repositories
  - services
  - `DiscoveryController`
- Why local refactor is unsafe:
  - любое UI change здесь легко сдвигает lifecycle dependency graph и side effects.
- Target decomposition:
  - app-level composition root outside feature UI
    - Legacy owner unloaded: `DiscoveryPage`
    - State seam closed: dependency lifecycle vs widget lifecycle
    - Justifying migration phase: Phase 2
  - `Discovery read/application model`
    - Legacy owner unloaded: `DiscoveryPage`-coordinated callbacks
    - State seam closed: screen consumes ready-made application boundary instead of wiring dependencies
    - Justifying migration phase: Phase 3
- Migration difficulty:
  - Medium-high. Wiring is centralized here but touches many flows.
- Deletion criteria:
  - screen stops constructing repositories/services/controllers
  - feature entrypoints stop using ad-hoc callbacks to cross into other features
- Evidence level:
  - Confirmed from code
- Source of truth:
  - `lib/features/discovery/presentation/discovery_page.dart` / `DiscoveryPage`, `AppDatabase.instance`, `DiscoveryController(...)`, `_openFriendsSheet`, `_openClipboardSheet`, `_openSettingsSheet`, `_openFileExplorer`, `_openHistorySheet`

### 4.3 `LanDiscoveryService`

- Declared role:
  - LAN discovery service
- Actual role:
  - transport host, packet registry, scenario dispatcher, protocol codec container
- Owned state:
  - UDP lifecycle and protocol-related runtime internals visible through start/send/decode surface
- Illegal responsibilities:
  - multiple scenario packet contracts in one class
  - packet encode/decode and send methods for discovery, transfer, friend, share, thumbnail, clipboard
  - implicit protocol router
- External dependencies:
  - UDP/network stack
  - controller-level handlers that interpret results
- Why local refactor is unsafe:
  - packet shape, dispatch and transport lifecycle are coupled. Adjusting one flow risks wire regressions in others.
- Target decomposition:
  - transport adapter
    - Legacy owner unloaded: `LanDiscoveryService`
    - State seam closed: socket lifecycle separate from scenario semantics
    - Justifying migration phase: Phase 4
  - packet codec set
    - Legacy owner unloaded: `LanDiscoveryService`
    - State seam closed: serialization contract separate from send/receive orchestration
    - Justifying migration phase: Phase 4
  - protocol handlers by scenario
    - Legacy owner unloaded: `LanDiscoveryService`
    - State seam closed: discovery/friend/share/clipboard/transfer event handling split
    - Justifying migration phase: Phase 4
- Migration difficulty:
  - High. Wire compatibility must not drift.
- Deletion criteria:
  - no single class retains transport + codec + scenario dispatch authority simultaneously
- Evidence level:
  - Confirmed from code
- Source of truth:
  - `lib/features/discovery/data/lan_discovery_service.dart` / `LanDiscoveryService`, `LANDA_DISCOVER_V1`, `LANDA_TRANSFER_REQUEST_V1`, `LANDA_CLIPBOARD_CATALOG_V1`, `start`, `sendTransferRequest`, `sendTransferDecision`, `sendShareCatalog`, `sendClipboardCatalog`, `_decodeTransferEnvelope`

### 4.4 `SharedFolderCacheRepository`

- Declared role:
  - repository for shared folder caches
- Actual role:
  - persistence layer, index builder, policy enforcer, cache rebinder, pruning orchestrator
- Owned state:
  - `shared_folder_caches` durable rows
  - JSON index file lifecycle
  - derived cache metadata during indexing flows
- Illegal responsibilities:
  - building owner selection cache
  - indexing folder contents
  - pruning caches by availability
  - rebinding caches to MAC
- External dependencies:
  - `AppDatabase`
  - filesystem
  - JSON index files
- Why local refactor is unsafe:
  - repository changes can alter persistence, file format and runtime behavior in one move.
- Target decomposition:
  - metadata persistence store
    - Legacy owner unloaded: `SharedFolderCacheRepository`
    - State seam closed: SQLite metadata separate from file index materialization
    - Justifying migration phase: Phase 5
  - index file store
    - Legacy owner unloaded: `SharedFolderCacheRepository`
    - State seam closed: JSON index read/write separate from catalog ownership
    - Justifying migration phase: Phase 5
  - cache catalog owner
    - Legacy owner unloaded: `SharedFolderCacheRepository`
    - State seam closed: single writer for cache metadata and index lifecycle decisions
    - Justifying migration phase: Phase 5
- Migration difficulty:
  - High. Dual persistence forms must stay consistent during cutover.
- Deletion criteria:
  - repository surface reduced to thin persistence adapter or removed in favor of narrower stores
- Evidence level:
  - Confirmed from code
- Source of truth:
  - `lib/features/transfer/data/shared_folder_cache_repository.dart` / `SharedFolderCacheRepository`, `upsertOwnerFolderCache`, `buildOwnerSelectionCache`, `saveReceiverCache`, `readIndexEntries`, `pruneUnavailableOwnerCaches`, `rebindOwnerCachesToMac`, `_indexFolder`

### 4.5 Files module / `file_explorer_*`

- Declared role:
  - file explorer UI
- Actual role:
  - part-based pseudo-module with shared private namespace instead of explicit feature boundaries
- Owned state:
  - explorer presentation state
  - preview cache state
  - local viewer behavior
  - explorer models and utility rules
- Illegal responsibilities:
  - module-wide state and behavior sharing through `part`
  - static preview cache in presentation layer
  - no explicit owner split between navigation state, preview lifecycle and viewer concerns
- External dependencies:
  - discovery entrypoints
  - transfer/shared cache data passed from outside
- Why local refactor is unsafe:
  - any change inside the part graph can silently reshape shared private state without contract boundaries.
- Target decomposition:
  - files feature state owner
    - Legacy owner unloaded: part-based page module
    - State seam closed: navigation/filter/sort/read-model ownership
    - Justifying migration phase: Phase 6
  - preview cache owner
    - Legacy owner unloaded: `_MediaPreviewCache`
    - State seam closed: preview artifact lifecycle separate from widget tree
    - Justifying migration phase: Phase 6
  - local viewer boundary
    - Legacy owner unloaded: shared part namespace
    - State seam closed: viewer actions separate from explorer state
    - Justifying migration phase: Phase 6
- Migration difficulty:
  - Medium-high. The module is structurally fake-decomposed already.
- Deletion criteria:
  - no `part / part of` graph carries feature-wide ownership
  - preview cache no longer lives as static presentation-global state
- Evidence level:
  - Confirmed from code
- Source of truth:
  - `lib/features/files/presentation/file_explorer_page.dart` / `part 'file_explorer/file_explorer_page_state.dart'`, `part 'file_explorer/media_preview_cache.dart'`, `part 'file_explorer/local_file_viewer.dart'`; `lib/features/files/presentation/file_explorer/file_explorer_page_state.dart` / `FileExplorerPage`; `lib/features/files/presentation/file_explorer/media_preview_cache.dart` / `_MediaPreviewCache`

### 4.6 `VideoLinkShareService`

- Declared role:
  - service for video link sharing
- Actual role:
  - session owner plus embedded HTTP flow handler plus HTML generator
- Owned state:
  - `activeSession`
- Illegal responsibilities:
  - session lifecycle
  - request routing
  - auth handling
  - watch page generation
  - stream handling
- External dependencies:
  - local HTTP serving mechanics
  - transfer/share flows that start or stop publication
- Why local refactor is unsafe:
  - one service change can break session lifecycle, auth and page generation together.
- Target decomposition:
  - keep as dedicated bounded subsystem for now
    - Legacy owner unloaded: none in earlier phases
    - State seam closed: video share session isolated from generic discovery controller
    - Justifying migration phase: not before main ownership split; secondary phase after Phase 6 if still needed
- Migration difficulty:
  - Medium. It is large, but less globally entangled than `DiscoveryController`.
- Deletion criteria:
  - if retained, its public API must shrink to session orchestration only; if replaced, HTTP/auth/page logic must move behind narrower collaborators
- Evidence level:
  - Confirmed from code
- Source of truth:
  - `lib/features/transfer/data/video_link_share_service.dart` / `VideoLinkShareService`, `activeSession`, `publish`, `stop`, `_handleRequest`, `_handleWatchPage`, `_handleAuth`, `_handleVideoStream`, `_buildWatchPageHtml`

### 4.7 `TransferStorageService`

- Declared role:
  - storage helper for transfer files
- Actual role:
  - path resolver, preview cache cleaner, publish helper, platform-specific side-effect holder
- Owned state:
  - no broad durable domain state visible, but owns storage-side decisions and preview cleanup policy
- Illegal responsibilities:
  - path resolution and filesystem policy are mixed with publish/export behavior and Android notification helpers
- External dependencies:
  - filesystem
  - platform-specific APIs
- Why local refactor is unsafe:
  - storage semantics and platform behaviors are packed together; filesystem changes may break platform-specific flows.
- Target decomposition:
  - keep narrow storage adapter + publish/export collaborator split later
    - Legacy owner unloaded: `TransferStorageService`
    - State seam closed: storage path resolution separate from publish/export and platform notifications
    - Justifying migration phase: after Phase 5, because shared cache and transfer ownership must stabilize first
- Migration difficulty:
  - Medium.
- Deletion criteria:
  - path resolution, preview cleanup, publish/export, platform notifications stop coexisting in one class
- Evidence level:
  - Confirmed from code
- Source of truth:
  - `lib/features/transfer/data/transfer_storage_service.dart` / `TransferStorageService`, `resolveReceiveDirectory`, `resolvePreviewDirectory`, `cleanupPreviewCache`, `publishToUserDownloads`

## 5. Source of Truth Audit

### 5.1 Device identity

- Current owners:
  - runtime device map in `DiscoveryController._devicesByIp`
  - alias/trust records in `known_devices` via `DeviceAliasRepository`
  - local device MAC derivation in `DiscoveryController._resolveLocalDeviceMac`
- Accidental primary owner:
  - `_devicesByIp` for live behavior, despite AGENTS contract saying MAC is identity key
- Target single owner:
  - `DeviceRegistry`
- Derived state:
  - active reachability by IP
- Projection:
  - discovery screen device list
- Cache:
  - last-known IP in `known_devices`
- Legacy mirrors to remove:
  - `DiscoveryController._devicesByIp` as identity truth
  - `DiscoveryController._aliasByMac` as separate identity mirror
- Migration path:
  - Phase 1 locks vocabulary and identity rules.
  - Phase 3 introduces `DeviceRegistry` as single writer for device identity mapping.
  - Read path switches first for discovery read models.
  - Write path switches second for seen-device updates and alias lookup.
  - `_devicesByIp` remains temporary reachability projection only until deletion proof.
- Evidence level:
  - Confirmed from code
- Source of truth:
  - `lib/features/discovery/application/discovery_controller.dart` / `_devicesByIp`, `_aliasByMac`, `_resolveLocalDeviceMac`
  - `lib/features/discovery/data/device_alias_repository.dart` / `recordSeenDevices`, `normalizeMac`
  - `lib/core/storage/app_database.dart` / `knownDevicesTable`

### 5.2 Peer identity

- Current owners:
  - IP-keyed runtime structures in discovery
  - `friends` durable records via `FriendRepository`
  - `local_peer_id` in `app_settings`
- Accidental primary owner:
  - mixed. No honest single owner exists.
- Target single owner:
  - split into `TrustedLanPeerStore`, `InternetPeerEndpointStore`, `LocalPeerIdentityStore`
- Derived state:
  - discovery-visible peer projections
- Projection:
  - friends/peer lists presented in UI
- Cache:
  - enabled/disabled peer endpoint snapshots in `friends`
- Legacy mirrors to remove:
  - `local_peer_id` ownership inside `FriendRepository`
  - implicit mapping between LAN trust and internet peer model
- Migration path:
  - Phase 1 extracts terminology and separates local peer identity from friend endpoint records.
  - Legacy reads remain through current repositories with adapter translation.
  - Writes move first for new local peer identity creation.
  - Writes for endpoint enable/disable move only after UI and protocol read paths stop assuming old shape.
- Evidence level:
  - Confirmed from code
- Source of truth:
  - `lib/features/discovery/data/friend_repository.dart` / `_localPeerIdKey`, `loadOrCreateLocalPeerId`, `listFriends`, `setFriendEnabled`
  - `lib/core/storage/app_database.dart` / `friendsTable`, `appSettingsTable`

### 5.3 Trust vs friend

- Current owners:
  - trust on LAN devices via `DeviceAliasRepository.loadTrustedMacs` and `setTrusted`
  - friend/internet endpoint list via `FriendRepository`
  - UI reads from discovery projections
- Accidental primary owner:
  - none. The same business word is overloaded onto incompatible stores.
- Target single owner:
  - `TrustedLanPeerStore` for trust
  - `InternetPeerEndpointStore` for internet peer endpoints
- Derived state:
  - unified UI sections that show “known peers”
- Projection:
  - screen groups and badges
- Cache:
  - any merged UI list is read-model only
- Legacy mirrors to remove:
  - any projection that treats trusted LAN device and internet friend as one durable entity
- Migration path:
  - Phase 1 resets vocabulary.
  - Phase 3 removes UI dependence on merged semantics.
  - no dual-write allowed between `known_devices.is_trusted` and `friends`.
- Evidence level:
  - Confirmed from code
- Source of truth:
  - `lib/features/discovery/data/device_alias_repository.dart` / `loadTrustedMacs`, `setTrusted`
  - `lib/features/discovery/data/friend_repository.dart` / `listFriends`, `upsertFriend`, `setFriendEnabled`

### 5.4 Shared cache metadata / index / projection

- Current owners:
  - SQLite metadata in `shared_folder_caches`
  - JSON index files managed by `SharedFolderCacheRepository`
  - controller mirrors in `_ownerSharedCaches` and `_ownerIndexEntriesByCacheId`
- Accidental primary owner:
  - mixed. Metadata and index lifecycle are split, while controller mirrors drive read path.
- Target single owner:
  - `SharedCacheCatalog`
- Derived state:
  - file explorer tree and filtered item lists
- Projection:
  - read models for explorer and remote share browsing
- Cache:
  - JSON index files remain cache/index materialization, not UI-owned truth
- Legacy mirrors to remove:
  - `_ownerSharedCaches`
  - `_ownerIndexEntriesByCacheId`
- Migration path:
  - Phase 5 introduces catalog owner with dual-read from legacy persistence artifacts.
  - Read path switches first for explorer/discovery projections.
  - Write path switches second for cache create/update/prune/rebind.
  - Dual-write between old controller mirrors and new catalog is forbidden.
- Evidence level:
  - Confirmed from code
- Source of truth:
  - `lib/features/transfer/data/shared_folder_cache_repository.dart` / `saveReceiverCache`, `readIndexEntries`, `pruneUnavailableOwnerCaches`, `rebindOwnerCachesToMac`
  - `lib/features/discovery/application/discovery_controller.dart` / `_ownerSharedCaches`, `_ownerIndexEntriesByCacheId`, `_loadOwnerCaches`
  - `lib/core/storage/app_database.dart` / `sharedFolderCachesTable`

### 5.5 Clipboard / history

- Current owners:
  - `ClipboardHistoryRepository` for durable history
  - `DiscoveryController._clipboardHistory` for in-memory mirrored history
  - remote clipboard projections in discovery runtime state
- Accidental primary owner:
  - controller for UI behavior, repository for durability
- Target single owner:
  - `ClipboardHistoryStore`
- Derived state:
  - selected remote clipboard source in UI
- Projection:
  - grouped/filtered clipboard lists
- Cache:
  - dedupe hash/check state internal to clipboard owner
- Legacy mirrors to remove:
  - `DiscoveryController._clipboardHistory`
- Migration path:
  - Phase 6 introduces dedicated store and keeps repository as persistence adapter.
  - Read path switches first in `ClipboardSheet`.
  - Write path switches second for capture insert/delete/trim flows.
  - remote clipboard projections remain separate session read-models, not durable history.
- Evidence level:
  - Confirmed from code
- Source of truth:
  - `lib/features/clipboard/data/clipboard_history_repository.dart` / `listRecent`, `findLatest`, `hasHash`, `insert`, `trimToMaxEntries`
  - `lib/features/discovery/application/discovery_controller.dart` / `_clipboardHistory`
  - `lib/features/clipboard/presentation/clipboard_sheet.dart` / `widget.controller.clipboardHistory`

### 5.6 Remote shares

- Current owners:
  - session-visible remote shares in `DiscoveryController._remoteShareOptions`
  - durable receiver cache rows via `SharedFolderCacheRepository.saveReceiverCache`
- Accidental primary owner:
  - controller for current session browsing
- Target single owner:
  - `RemoteShareBrowser` for session state
  - `SharedCacheCatalog` for persisted receiver cache artifacts
- Derived state:
  - page-local selection/filter
- Projection:
  - file explorer remote listing
- Cache:
  - receiver cache metadata/index persisted by shared cache subsystem
- Legacy mirrors to remove:
  - `_remoteShareOptions` as multi-purpose truth
- Migration path:
  - Phase 5 stabilizes persisted receiver cache ownership.
  - Phase 6 moves session browse state out of discovery owner.
  - dual-write from remote browse state directly into controller and repository is forbidden.
- Evidence level:
  - Confirmed from code
- Source of truth:
  - `lib/features/discovery/application/discovery_controller.dart` / `_remoteShareOptions`, `_handleShareCatalog`
  - `lib/features/transfer/data/shared_folder_cache_repository.dart` / `saveReceiverCache`

### 5.7 Transfer / session state

- Current owners:
  - transfer negotiation in `LanDiscoveryService` + `DiscoveryController`
  - file transfer execution in `FileTransferService`
  - video link share session in `VideoLinkShareService.activeSession`
- Accidental primary owner:
  - none. Session ownership is fragmented by protocol stage.
- Target single owner:
  - `TransferSessionCoordinator`
- Derived state:
  - progress/status read models
- Projection:
  - transfer history lists and current transfer cards
- Cache:
  - `transfer_history` remains durable audit/history store, not live session owner
- Legacy mirrors to remove:
  - transfer negotiation state embedded in discovery callbacks
- Migration path:
  - Phase 4 isolates protocol handlers.
  - Phase 6 routes session commands/results through coordinator.
  - read path for session state switches before write authority cutover.
- Evidence level:
  - Strong inference from code structure
- Source of truth:
  - `lib/features/discovery/application/discovery_controller.dart` / `_onTransferRequest`, `_onTransferDecision`
  - `lib/features/discovery/data/lan_discovery_service.dart` / `sendTransferRequest`, `sendTransferDecision`
  - `lib/features/transfer/data/file_transfer_service.dart` / `sendFiles`, `startReceiver`
  - `lib/features/transfer/data/video_link_share_service.dart` / `activeSession`

### 5.8 Settings vs local identity

- Current owners:
  - `AppSettingsRepository` for app settings
  - `FriendRepository` for `local_peer_id` inside `app_settings`
- Accidental primary owner:
  - `FriendRepository` for identity creation, `AppSettingsRepository` for the underlying table
- Target single owner:
  - `LocalPeerIdentityStore` for local peer identity
  - `SettingsStore` for app settings only
- Derived state:
  - UI forms and toggles
- Projection:
  - current settings screen model
- Cache:
  - in-memory loaded settings snapshot
- Legacy mirrors to remove:
  - `FriendRepository._localPeerIdKey` authority
- Migration path:
  - Phase 1 creates explicit ownership split.
  - dual-read from `app_settings` is allowed during transition.
  - dual-write from both `FriendRepository` and `LocalPeerIdentityStore` is forbidden.
- Evidence level:
  - Confirmed from code
- Source of truth:
  - `lib/features/discovery/data/friend_repository.dart` / `_localPeerIdKey`, `loadOrCreateLocalPeerId`
  - `lib/features/settings/data/app_settings_repository.dart` / `load`, `save`
  - `lib/core/storage/app_database.dart` / `appSettingsTable`

### 5.9 Page-local state vs feature/application state

- Current owners:
  - `DiscoveryPage` for feature launch lifecycle
  - `ClipboardSheet` local selected remote IP
  - file explorer part-based page state
  - `DiscoveryController` for cross-feature application state
- Accidental primary owner:
  - page widgets for some flows, controller for others, with no explicit seam
- Target single owner:
  - page-local widgets keep ephemeral selection only
  - feature/application owners keep durable or session truth
- Derived state:
  - selected tab, selected remote item, current sort mode
- Projection:
  - read models passed into widgets
- Cache:
  - none unless explicit preview/session cache owner declares it
- Legacy mirrors to remove:
  - page widgets acting as fallback owner for application state
- Migration path:
  - Phase 2 removes dependency composition from page.
  - Phase 6 finalizes separation between page-local ephemeral state and feature/application owners.
- Evidence level:
  - Confirmed from code
- Source of truth:
  - `lib/features/discovery/presentation/discovery_page.dart` / `_openFileExplorer`, `_openClipboardSheet`
  - `lib/features/clipboard/presentation/clipboard_sheet.dart` / `_selectedRemoteIp`
  - `lib/features/files/presentation/file_explorer/file_explorer_page_state.dart` / `FileExplorerPage`

## 6. Vocabulary and Domain Model Reset

### `friend`

- Current ambiguous usage:
  - internet endpoint relation in `friends`
  - informal UI label overlapping with trusted LAN devices
- Why it breaks architecture:
  - mixes social/endpoint semantics with LAN trust semantics
- New meaning:
  - persistent internet peer endpoint record only
- Allowed usage:
  - `friends` table replacement/migration context
  - endpoint enable/disable state
- Forbidden usage:
  - trusted LAN device
  - local device identity
  - generic “known peer”
- Evidence level:
  - Confirmed from code
- Source of truth:
  - `lib/features/discovery/data/friend_repository.dart` / `listFriends`, `upsertFriend`, `setFriendEnabled`

### `trusted device`

- Current ambiguous usage:
  - device in `known_devices` with trust bit, but sometimes treated as a friend-like entity in UI flows
- Why it breaks architecture:
  - trust becomes overloaded with endpoint identity and relationship semantics
- New meaning:
  - LAN device keyed by normalized MAC with explicit trust state
- Allowed usage:
  - trust decisions
  - trusted LAN discovery list
- Forbidden usage:
  - internet endpoint
  - share session owner
- Evidence level:
  - Confirmed from code
- Source of truth:
  - `lib/features/discovery/data/device_alias_repository.dart` / `loadTrustedMacs`, `setTrusted`, `normalizeMac`

### `peer`

- Current ambiguous usage:
  - sometimes device on LAN, sometimes internet endpoint, sometimes session counterparty
- Why it breaks architecture:
  - one term hides different identity keys and lifecycles
- New meaning:
  - generic counterparty umbrella term only when subtype is explicitly named nearby
- Allowed usage:
  - `LAN peer`, `internet peer`, `remote peer session`
- Forbidden usage:
  - standalone durable model name
- Evidence level:
  - Strong inference from code structure
- Source of truth:
  - `lib/features/discovery/domain/friend_peer.dart` / `FriendPeer`
  - `lib/features/discovery/domain/discovered_device.dart` / `DiscoveredDevice`

### `local peer`

- Current ambiguous usage:
  - local identity key stored through friend repository
- Why it breaks architecture:
  - local identity is not a friend relation
- New meaning:
  - identity of this app instance for external peer protocols
- Allowed usage:
  - local peer identity store
  - protocol self-identification
- Forbidden usage:
  - settings blob key owned by friend subsystem
- Evidence level:
  - Confirmed from code
- Source of truth:
  - `lib/features/discovery/data/friend_repository.dart` / `_localPeerIdKey`, `loadOrCreateLocalPeerId`

### `internet peer`

- Current ambiguous usage:
  - partially overlaps with friend records
- Why it breaks architecture:
  - endpoint persistence and relationship semantics are fused
- New meaning:
  - remote endpoint reachable through non-LAN friend/invite flow with explicit endpoint data and enabled state
- Allowed usage:
  - endpoint store
  - invitation / enabled/disabled endpoint flows
- Forbidden usage:
  - LAN trust
- Evidence level:
  - Confirmed from code
- Source of truth:
  - `lib/features/discovery/data/friend_repository.dart` / `FriendRepository`
  - `lib/features/discovery/domain/friend_peer.dart` / `FriendPeer`

### `device`

- Current ambiguous usage:
  - runtime IP-visible host and stable MAC-visible identity both called device
- Why it breaks architecture:
  - reachability projection and durable identity are conflated
- New meaning:
  - stable LAN hardware identity keyed by normalized MAC when available
- Allowed usage:
  - device registry
  - trust/alias ownership
- Forbidden usage:
  - ephemeral IP-only session without stable identity mapping
- Evidence level:
  - Confirmed from code
- Source of truth:
  - `lib/features/discovery/data/device_alias_repository.dart` / `normalizeMac`
  - `lib/features/discovery/application/discovery_controller.dart` / `_devicesByIp`

### `session`

- Current ambiguous usage:
  - active video share, active transfer negotiation, remote browse interaction all use session-like behavior without one model
- Why it breaks architecture:
  - lifecycle boundaries disappear
- New meaning:
  - bounded ephemeral runtime interaction with explicit start/end and one owner
- Allowed usage:
  - transfer session
  - video share session
  - remote browse session
- Forbidden usage:
  - persistent relationship records
- Evidence level:
  - Strong inference from code structure
- Source of truth:
  - `lib/features/transfer/data/video_link_share_service.dart` / `activeSession`
  - `lib/features/discovery/application/discovery_controller.dart` / transfer/share handlers

### `shared folder cache`

- Current ambiguous usage:
  - durable metadata row, JSON index file and UI-visible projection are treated as one thing
- Why it breaks architecture:
  - one term hides three different artifacts with different writers
- New meaning:
  - durable catalog entry whose index materialization is a managed artifact
- Allowed usage:
  - shared cache catalog owner
- Forbidden usage:
  - direct synonym for JSON file only
- Evidence level:
  - Confirmed from code
- Source of truth:
  - `lib/features/transfer/data/shared_folder_cache_repository.dart` / `saveReceiverCache`, `readIndexEntries`
  - `lib/features/transfer/domain/shared_folder_cache.dart` / `SharedFolderCache`

### `catalog`

- Current ambiguous usage:
  - share catalog packet and local cache list are not clearly separated
- Why it breaks architecture:
  - remote session payload and durable local catalog collapse into one idea
- New meaning:
  - durable or session-scoped list authority owned by a specific store/browser
- Allowed usage:
  - `SharedCacheCatalog`
  - remote share browse catalog if marked as session catalog
- Forbidden usage:
  - generic synonym for any list of files without owner
- Evidence level:
  - Strong inference from code structure
- Source of truth:
  - `lib/features/discovery/data/lan_discovery_service.dart` / `sendShareCatalog`
  - `lib/features/transfer/data/shared_folder_cache_repository.dart` / cache list APIs

### `index`

- Current ambiguous usage:
  - index file contents and runtime entry list
- Why it breaks architecture:
  - file artifact and in-memory projection get conflated
- New meaning:
  - serialized file-entry materialization for a cache catalog entry
- Allowed usage:
  - JSON index file
  - index store
- Forbidden usage:
  - direct name for UI tree state
- Evidence level:
  - Confirmed from code
- Source of truth:
  - `lib/features/transfer/data/shared_folder_cache_repository.dart` / `readIndexEntries`, `_indexFolder`

### `projection`

- Current ambiguous usage:
  - not consistently named, so mirrors are mistaken for truth
- Why it breaks architecture:
  - read-models become accidental owners
- New meaning:
  - rebuildable read-only representation derived from a single writer
- Allowed usage:
  - discovery list models
  - explorer tree/view models
- Forbidden usage:
  - mutable source-of-truth store
- Evidence level:
  - Strong inference from code structure
- Source of truth:
  - `lib/features/discovery/application/discovery_controller.dart` / controller mirrors used for UI-facing access

## 7. Target Ownership Model

### 7.1 `DeviceRegistry`

- Legacy owner unloaded:
  - `DiscoveryController`
- State seam closed:
  - stable device identity keyed by MAC vs transient reachability keyed by IP
- Phase introduced:
  - Phase 3
- Why this split is justified now:
  - discovery read path cannot be stabilized while identity is split between `_devicesByIp` and `known_devices`.
- Owned state:
  - durable device identity mapping and last-seen device metadata
- May mutate:
  - normalized device records and last-known reachability identity mapping
- Reads only:
  - raw discovery packets / seen-device observations
- Commands:
  - record seen device
  - update alias mapping input
  - resolve stable device identity
- Results/events out:
  - device registry updated
  - device projection invalidated
- Lifecycle:
  - app-scoped
- Durable or ephemeral:
  - durable core plus ephemeral reachability projection
- Session-scoped or persistent:
  - persistent owner
- Single write authority:
  - `DeviceRegistry`
- Forbidden writers:
  - `DiscoveryController`
  - widgets
  - helpers/extensions
  - repositories writing around registry callbacks
- Forbidden dual-write paths:
  - simultaneous writes to `_devicesByIp` as identity truth and `known_devices`
- What it must never do:
  - own UI state
  - send network packets
  - decide trust or friend semantics
- Evidence level:
  - Strong inference from code structure

### 7.2 `TrustedLanPeerStore`

- Legacy owner unloaded:
  - `DiscoveryController`, `DeviceAliasRepository` as implicit business owner
- State seam closed:
  - trust model separate from generic device registry and internet peer endpoints
- Phase introduced:
  - Phase 3
- Why this split is justified now:
  - trust bit already exists in `known_devices`, but it is being consumed without clear ownership boundary.
- Owned state:
  - trust status for LAN devices keyed by normalized MAC
- May mutate:
  - trust flags only
- Reads only:
  - device identity records from `DeviceRegistry`
- Commands:
  - trust device
  - revoke trust
  - query trusted LAN peers
- Results/events out:
  - trusted peer set changed
- Lifecycle:
  - app-scoped
- Durable or ephemeral:
  - durable
- Session-scoped or persistent:
  - persistent
- Single write authority:
  - `TrustedLanPeerStore`
- Forbidden writers:
  - `DiscoveryController`
  - `DiscoveryPage`
  - `FriendRepository`
- Forbidden dual-write paths:
  - mirrored writes to `friends` and `known_devices.is_trusted`
- What it must never do:
  - create internet peers
  - own transport session data
- Evidence level:
  - Strong inference from code structure

### 7.3 `InternetPeerEndpointStore`

- Legacy owner unloaded:
  - `FriendRepository` as overloaded owner of both friend semantics and local identity
- State seam closed:
  - internet endpoint persistence separate from local identity and LAN trust
- Phase introduced:
  - Phase 1
- Why this split is justified now:
  - `friends` data already exists and must stop carrying unrelated semantics before deeper controller split.
- Owned state:
  - persistent endpoint records and enabled flags
- May mutate:
  - endpoint metadata and enabled state
- Reads only:
  - local peer identity
- Commands:
  - list endpoints
  - upsert endpoint
  - disable endpoint
  - remove endpoint
- Results/events out:
  - endpoint list changed
- Lifecycle:
  - app-scoped
- Durable or ephemeral:
  - durable
- Session-scoped or persistent:
  - persistent
- Single write authority:
  - `InternetPeerEndpointStore`
- Forbidden writers:
  - `DiscoveryController`
  - widgets
  - `TrustedLanPeerStore`
- Forbidden dual-write paths:
  - writing friend-like state into both `friends` and `known_devices`
- What it must never do:
  - own LAN trust
  - own local peer identity
- Evidence level:
  - Strong inference from code structure

### 7.4 `LocalPeerIdentityStore`

- Legacy owner unloaded:
  - `FriendRepository`
- State seam closed:
  - local peer identity separate from app settings and internet endpoint list
- Phase introduced:
  - Phase 1
- Why this split is justified now:
  - `_localPeerIdKey` is already a contract violation visible in Dart.
- Owned state:
  - local peer identity value
- May mutate:
  - create/rotate identity according to protocol policy
- Reads only:
  - storage adapter only
- Commands:
  - load identity
  - create identity if absent
- Results/events out:
  - identity available
- Lifecycle:
  - app-scoped
- Durable or ephemeral:
  - durable
- Session-scoped or persistent:
  - persistent
- Single write authority:
  - `LocalPeerIdentityStore`
- Forbidden writers:
  - `FriendRepository`
  - `DiscoveryController`
  - settings UI closures
- Forbidden dual-write paths:
  - writes from both `FriendRepository.loadOrCreateLocalPeerId` and new store
- What it must never do:
  - own settings bundle
  - own friend/invite list
- Evidence level:
  - Strong inference from code structure

### 7.5 `SharedCacheCatalog`

- Legacy owner unloaded:
  - `SharedFolderCacheRepository`, `DiscoveryController`
- State seam closed:
  - single-writer ownership over shared cache metadata and index lifecycle
- Phase introduced:
  - Phase 5
- Why this split is justified now:
  - cannot safely extract files feature or remote share browser while cache truth is split across DB, JSON and controller mirrors.
- Owned state:
  - shared cache metadata and index materialization lifecycle
- May mutate:
  - create/update/rebind/prune cache entries
- Reads only:
  - filesystem scan outputs and remote share payload inputs
- Commands:
  - create owner cache
  - save receiver cache
  - rebind cache
  - prune cache
  - read cache catalog/query projections
- Results/events out:
  - catalog changed
  - cache index available/invalidated
- Lifecycle:
  - app-scoped
- Durable or ephemeral:
  - durable owner with rebuildable projections
- Session-scoped or persistent:
  - persistent
- Single write authority:
  - `SharedCacheCatalog`
- Forbidden writers:
  - `DiscoveryController`
  - file explorer widgets
  - ad-hoc repository callbacks
- Forbidden dual-write paths:
  - simultaneous direct writes to `shared_folder_caches` and controller mirrors
  - direct UI-triggered JSON index writes bypassing catalog
- What it must never do:
  - own widget state
  - own transport sessions
- Evidence level:
  - Strong inference from code structure

### 7.6 `ClipboardHistoryStore`

- Legacy owner unloaded:
  - `DiscoveryController`
- State seam closed:
  - durable local clipboard history separate from session remote clipboard projections
- Phase introduced:
  - Phase 6
- Why this split is justified now:
  - clipboard flows are currently discovery-owned, blocking feature isolation.
- Owned state:
  - local clipboard history and dedupe policy
- May mutate:
  - insert/delete/trim local history
- Reads only:
  - clipboard capture observations
- Commands:
  - append clipboard entry
  - trim history
  - query recent history
- Results/events out:
  - history changed
- Lifecycle:
  - app-scoped
- Durable or ephemeral:
  - durable
- Session-scoped or persistent:
  - persistent
- Single write authority:
  - `ClipboardHistoryStore`
- Forbidden writers:
  - `DiscoveryController`
  - `ClipboardSheet`
  - repository callbacks that modify UI state directly
- Forbidden dual-write paths:
  - writes to repository and controller mirror in the same action path
- What it must never do:
  - own selected remote source UI state
  - own network clipboard protocol
- Evidence level:
  - Strong inference from code structure

### 7.7 `TransferSessionCoordinator`

- Legacy owner unloaded:
  - `DiscoveryController` and protocol-callback glue
- State seam closed:
  - transfer/session orchestration separate from transport and persistence
- Phase introduced:
  - Phase 6, after Phase 4 protocol split
- Why this split is justified now:
  - session ownership cannot be made explicit before handlers and packet boundaries are separated.
- Owned state:
  - active transfer negotiations and runtime transfer sessions
- May mutate:
  - session lifecycle only
- Reads only:
  - packet handler events, file transfer execution results, storage results
- Commands:
  - start outbound transfer session
  - accept/reject inbound transfer
  - observe progress
  - finalize session
- Results/events out:
  - transfer session opened/updated/completed/failed
- Lifecycle:
  - app-scoped runtime owner
- Durable or ephemeral:
  - ephemeral owner with history writes delegated elsewhere
- Session-scoped or persistent:
  - session-scoped
- Single write authority:
  - `TransferSessionCoordinator`
- Forbidden writers:
  - widgets
  - `LanDiscoveryService`
  - `FileTransferService`
  - `VideoLinkShareService`
- Forbidden dual-write paths:
  - direct controller session mutation alongside coordinator session mutation
- What it must never do:
  - own transport socket lifecycle
  - write transfer history directly outside its contracted persistence port
- Evidence level:
  - Strong inference from code structure

### 7.8 `RemoteShareBrowser`

- Legacy owner unloaded:
  - `DiscoveryController`
- State seam closed:
  - session browse state separate from persisted shared cache catalog
- Phase introduced:
  - Phase 6, after Phase 5 cache stabilization
- Why this split is justified now:
  - remote share browsing cannot be safely isolated until receiver cache ownership is stabilized.
- Owned state:
  - active remote browse session state and current remote catalog projection
- May mutate:
  - current browse session only
- Reads only:
  - protocol share catalog packets
  - persisted receiver cache snapshots from `SharedCacheCatalog`
- Commands:
  - start browse session
  - receive catalog update
  - select remote path/filter
- Results/events out:
  - browse projection changed
- Lifecycle:
  - screen/session-scoped
- Durable or ephemeral:
  - ephemeral
- Session-scoped or persistent:
  - session-scoped
- Single write authority:
  - `RemoteShareBrowser`
- Forbidden writers:
  - `DiscoveryController`
  - file explorer widgets
  - `SharedCacheCatalog`
- Forbidden dual-write paths:
  - writing session browse state into both controller and cache catalog
- What it must never do:
  - mutate durable cache metadata directly
- Evidence level:
  - Strong inference from code structure

### 7.9 `SettingsStore`

- Legacy owner unloaded:
  - `DiscoveryController` for settings load/save orchestration
- State seam closed:
  - app settings separate from local peer identity and feature runtime state
- Phase introduced:
  - Phase 1
- Why this split is justified now:
  - settings contract exists already and must stop being a catch-all table owner.
- Owned state:
  - app settings values currently stored by `AppSettingsRepository`
- May mutate:
  - settings only
- Reads only:
  - storage adapter
- Commands:
  - load settings
  - save settings
- Results/events out:
  - settings changed
- Lifecycle:
  - app-scoped
- Durable or ephemeral:
  - durable
- Session-scoped or persistent:
  - persistent
- Single write authority:
  - `SettingsStore`
- Forbidden writers:
  - `DiscoveryController`
  - `FriendRepository`
  - arbitrary feature widgets
- Forbidden dual-write paths:
  - parallel writes from settings repository and controller-owned mirrors
- What it must never do:
  - create local peer identity
  - own trust/friend state
- Evidence level:
  - Strong inference from code structure

### 7.10 `Discovery read/application model`

- Legacy owner unloaded:
  - `DiscoveryController`, `DiscoveryPage`
- State seam closed:
  - discovery UI projection separate from durable/session owners
- Phase introduced:
  - Phase 3
- Why this split is justified now:
  - page composition was removed in Phase 2; now the UI needs a thin application boundary.
- Owned state:
  - discovery screen projection only
- May mutate:
  - ephemeral screen-level filters/sort/search if any
- Reads only:
  - `DeviceRegistry`, `TrustedLanPeerStore`, `InternetPeerEndpointStore`, `RemoteShareBrowser`, `TransferSessionCoordinator`
- Commands:
  - refresh projection
  - dispatch user intents to proper owners
- Results/events out:
  - UI-ready discovery model
- Lifecycle:
  - screen-scoped
- Durable or ephemeral:
  - ephemeral
- Session-scoped or persistent:
  - screen-scoped
- Single write authority:
  - own projection state only
- Forbidden writers:
  - repositories
  - widgets mutating durable state directly through callbacks
- Forbidden dual-write paths:
  - direct projection writes alongside owner writes to the same domain state
- What it must never do:
  - become a new god-controller
- Evidence level:
  - Strong inference from code structure

### 7.11 `Files feature state owner`

- Legacy owner unloaded:
  - `file_explorer_*` part graph
- State seam closed:
  - explorer navigation/filter/sort/read-model ownership separated from widgets and preview cache
- Phase introduced:
  - Phase 6
- Why this split is justified now:
  - feature cannot be isolated while its state is hidden in `part`-shared namespace and driven from discovery callbacks.
- Owned state:
  - explorer navigation and view state
- May mutate:
  - current path, sort, filter, selection, derived explorer projections
- Reads only:
  - cache catalog and remote browse session data
- Commands:
  - open path
  - change sort/filter
  - select item
- Results/events out:
  - explorer state changed
- Lifecycle:
  - screen-scoped
- Durable or ephemeral:
  - ephemeral
- Session-scoped or persistent:
  - screen-scoped
- Single write authority:
  - `Files feature state owner`
- Forbidden writers:
  - widgets
  - `DiscoveryController`
  - `_MediaPreviewCache`
- Forbidden dual-write paths:
  - view-state writes duplicated into page local state and owner state
- What it must never do:
  - write shared cache metadata directly
- Evidence level:
  - Strong inference from code structure

### 7.12 `Preview cache owner`

- Legacy owner unloaded:
  - `_MediaPreviewCache`
- State seam closed:
  - preview artifact lifecycle separate from explorer and widget tree
- Phase introduced:
  - Phase 6
- Why this split is justified now:
  - current static presentation cache prevents explicit lifecycle and deletion rules.
- Owned state:
  - preview artifact index and cleanup policy
- May mutate:
  - preview cache entries and cleanup scheduling
- Reads only:
  - file item metadata and storage paths
- Commands:
  - request preview
  - invalidate preview
  - cleanup preview cache
- Results/events out:
  - preview ready / preview invalidated
- Lifecycle:
  - app-scoped or feature-scoped depending on final performance constraints
- Durable or ephemeral:
  - ephemeral cache with durable backing files if needed
- Session-scoped or persistent:
  - app-scoped cache owner
- Single write authority:
  - `Preview cache owner`
- Forbidden writers:
  - widgets
  - `DiscoveryController`
  - `TransferStorageService` direct UI callbacks
- Forbidden dual-write paths:
  - direct writes to preview files from widgets while owner tracks cache state
- What it must never do:
  - own explorer navigation state
  - own transfer storage policy outside preview artifacts
- Evidence level:
  - Strong inference from code structure

## 8. Contract Map

### 8.1 `DeviceRegistry`

| Commands | Queries | Events In | Events Out | Allowed dependencies | Forbidden dependencies | Write authority | Read authority | Forbidden direct writes | Forbidden dual-write paths |
| --- | --- | --- | --- | --- | --- | --- | --- | --- | --- |
| `recordSeenDevice`, `updateAliasInput`, `resolveDevice` | `getDeviceByMac`, `listVisibleDevices` | discovery observations | `deviceRegistryChanged` | storage adapter for `known_devices`, discovery observation adapter | widgets, `LanDiscoveryService`, file explorer | `DeviceRegistry` only | discovery read model, trust store | controller fields, widget callbacks, helper static functions | `_devicesByIp` as identity truth plus direct DB writes |

### 8.2 `TrustedLanPeerStore`

| Commands | Queries | Events In | Events Out | Allowed dependencies | Forbidden dependencies | Write authority | Read authority | Forbidden direct writes | Forbidden dual-write paths |
| --- | --- | --- | --- | --- | --- | --- | --- | --- | --- |
| `trustDevice`, `revokeTrust` | `isTrusted`, `listTrustedPeers` | trusted toggle intent, registry updates | `trustedPeersChanged` | `DeviceRegistry`, `known_devices` persistence adapter | `FriendRepository`, widgets, transport service | `TrustedLanPeerStore` only | discovery read model | direct writes to `known_devices.is_trusted` from controller or widget | syncing trust into `friends` |

### 8.3 `InternetPeerEndpointStore`

| Commands | Queries | Events In | Events Out | Allowed dependencies | Forbidden dependencies | Write authority | Read authority | Forbidden direct writes | Forbidden dual-write paths |
| --- | --- | --- | --- | --- | --- | --- | --- | --- | --- |
| `upsertEndpoint`, `setEndpointEnabled`, `removeEndpoint` | `listEndpoints`, `findEndpoint` | invite/import actions | `internetEndpointsChanged` | `friends` persistence adapter, local peer identity read | trust store, widgets, discovery page | `InternetPeerEndpointStore` only | discovery read model, peer UI | direct writes to `friends` from controller/widget | mirrored writes to `friends` and `known_devices` |

### 8.4 `LocalPeerIdentityStore`

| Commands | Queries | Events In | Events Out | Allowed dependencies | Forbidden dependencies | Write authority | Read authority | Forbidden direct writes | Forbidden dual-write paths |
| --- | --- | --- | --- | --- | --- | --- | --- | --- | --- |
| `loadIdentity`, `createIdentityIfMissing` | `getIdentity` | app bootstrap | `localPeerIdentityReady` | storage adapter for `app_settings` or dedicated store | `FriendRepository`, widgets | `LocalPeerIdentityStore` only | endpoint store, protocol setup | direct writes via `FriendRepository._localPeerIdKey` | `FriendRepository` plus new store writing same key |

### 8.5 `SharedCacheCatalog`

| Commands | Queries | Events In | Events Out | Allowed dependencies | Forbidden dependencies | Write authority | Read authority | Forbidden direct writes | Forbidden dual-write paths |
| --- | --- | --- | --- | --- | --- | --- | --- | --- | --- |
| `createOwnerCache`, `saveReceiverCache`, `rebindCache`, `pruneCache` | `listCaches`, `readCacheIndex`, `findCache` | filesystem scan results, remote share payloads | `sharedCacheCatalogChanged`, `cacheIndexChanged` | metadata persistence store, index file store | widgets, discovery controller, preview cache owner | `SharedCacheCatalog` only | files owner, remote share browser, discovery read model | direct writes to DB rows or JSON index files from controller/widgets | direct DB+controller mirror dual-write |

### 8.6 `ClipboardHistoryStore`

| Commands | Queries | Events In | Events Out | Allowed dependencies | Forbidden dependencies | Write authority | Read authority | Forbidden direct writes | Forbidden dual-write paths |
| --- | --- | --- | --- | --- | --- | --- | --- | --- | --- |
| `appendEntry`, `deleteEntry`, `trimHistory` | `listRecent`, `findLatest` | clipboard capture events | `clipboardHistoryChanged` | clipboard persistence adapter, capture observation input | `DiscoveryController`, widgets, protocol handlers | `ClipboardHistoryStore` only | clipboard UI, discovery read model if still needed | controller mirror writes | repository write plus controller mirror write |

### 8.7 `TransferSessionCoordinator`

| Commands | Queries | Events In | Events Out | Allowed dependencies | Forbidden dependencies | Write authority | Read authority | Forbidden direct writes | Forbidden dual-write paths |
| --- | --- | --- | --- | --- | --- | --- | --- | --- | --- |
| `startOutbound`, `acceptInbound`, `rejectInbound`, `observeProgress`, `finalizeSession` | `listActiveSessions`, `findSession` | protocol handler events, file transfer results | `transferSessionChanged`, `transferCompleted`, `transferFailed` | protocol handlers, `FileTransferService`, storage adapter, history persistence | widgets, `LanDiscoveryService` raw transport, `DiscoveryController` | `TransferSessionCoordinator` only | discovery read model, transfer UI | direct controller session mutation | controller+coordinator live session dual-write |

### 8.8 `RemoteShareBrowser`

| Commands | Queries | Events In | Events Out | Allowed dependencies | Forbidden dependencies | Write authority | Read authority | Forbidden direct writes | Forbidden dual-write paths |
| --- | --- | --- | --- | --- | --- | --- | --- | --- | --- |
| `startBrowse`, `applyRemoteCatalog`, `selectPath`, `setFilter` | `currentBrowseProjection` | share catalog packets, cache snapshot updates | `remoteBrowseChanged` | protocol share handler, `SharedCacheCatalog` read | widgets, `DiscoveryController`, persistence writes | `RemoteShareBrowser` only | files owner, discovery read model | widget writes into session state | writing browse state into both browser and catalog |

### 8.9 `SettingsStore`

| Commands | Queries | Events In | Events Out | Allowed dependencies | Forbidden dependencies | Write authority | Read authority | Forbidden direct writes | Forbidden dual-write paths |
| --- | --- | --- | --- | --- | --- | --- | --- | --- | --- |
| `loadSettings`, `saveSettings` | `currentSettings` | app bootstrap, settings UI intent | `settingsChanged` | `AppSettingsRepository` or equivalent settings persistence port | `FriendRepository`, discovery page, widgets bypassing store | `SettingsStore` only | settings UI, other owners via read-only contract | direct `app_settings` writes from unrelated repositories | settings writes from controller and store in parallel |

### 8.10 `Discovery read/application model`

| Commands | Queries | Events In | Events Out | Allowed dependencies | Forbidden dependencies | Write authority | Read authority | Forbidden direct writes | Forbidden dual-write paths |
| --- | --- | --- | --- | --- | --- | --- | --- | --- | --- |
| `refreshProjection`, `dispatchIntent` | `currentDiscoveryView` | events from owners above | `discoveryViewChanged` | all read-only owner interfaces | raw repositories, transport adapter, file IO services | its own projection only | discovery UI | durable-state writes from UI convenience callbacks | projection writes pretending to mutate owner state |

### 8.11 `Files feature state owner`

| Commands | Queries | Events In | Events Out | Allowed dependencies | Forbidden dependencies | Write authority | Read authority | Forbidden direct writes | Forbidden dual-write paths |
| --- | --- | --- | --- | --- | --- | --- | --- | --- | --- |
| `openPath`, `setSort`, `setFilter`, `selectItem` | `currentExplorerState` | cache catalog updates, remote browse updates | `filesViewChanged` | `SharedCacheCatalog` read, `RemoteShareBrowser` read, preview cache owner | direct persistence adapters, discovery controller | its own feature state only | files UI | widget-local mirrors acting as hidden owners | page state plus owner state duplicated |

### 8.12 `Preview cache owner`

| Commands | Queries | Events In | Events Out | Allowed dependencies | Forbidden dependencies | Write authority | Read authority | Forbidden direct writes | Forbidden dual-write paths |
| --- | --- | --- | --- | --- | --- | --- | --- | --- | --- |
| `requestPreview`, `invalidatePreview`, `cleanup` | `getPreviewForKey` | file preview requests, storage cleanup ticks | `previewReady`, `previewInvalidated` | storage path adapter, media probing utilities | widgets, discovery controller, cache catalog writes | `Preview cache owner` only | files owner, viewer UI | direct file writes from widgets | widget-generated preview files plus owner-managed cache state |

Missing artifact:
- Final interface shapes for target owners are not implemented yet, so command names are contract placeholders.

Impact of uncertainty:
- Method naming may change, but write authority and forbidden dependency rules must not change.

Safest interim assumption:
- Preserve single-writer semantics even if concrete API names are adjusted during implementation.

## 9. Migration Ledger

| Migration item | Current owner | Target owner | Legacy read path | Target read path | Legacy write path | Target write path | Temporary adapter/bridge | Cutover condition | Rollback concern | Deletion trigger | Evidence level |
| --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- |
| Device identity | `DiscoveryController._devicesByIp`, `DeviceAliasRepository` | `DeviceRegistry` | discovery UI reads controller maps | discovery UI reads registry projection | `recordSeenDevices` + controller mirrors | registry writes via persistence adapter | `DeviceIdentityBridge` | discovery list and alias resolution no longer read controller identity maps | wrong IP/MAC association can hide devices | remove `_devicesByIp` as identity truth after Phase 3 verification | Confirmed from code |
| Trust/friend model | `DeviceAliasRepository`, `FriendRepository`, UI projections | `TrustedLanPeerStore` + `InternetPeerEndpointStore` | UI merges current discovery/friend outputs | UI reads separate trust and internet endpoint projections | `setTrusted`, `upsertFriend`, `setFriendEnabled` | writes routed to dedicated stores | `PeerVocabularyAdapter` | no UI flow treats trusted LAN device as friend record | migration can split one legacy screen into two lists unexpectedly | delete merged semantics after Phase 3 UI cutover | Confirmed from code |
| Discovery state | `DiscoveryController` | `Discovery read/application model` + dedicated owners | widgets read controller directly | widgets read thin discovery model | controller mutates its own broad state | writes delegated to target owners | `LegacyDiscoveryFacade` | `DiscoveryPage` stops depending on broad controller surface | missing callback compatibility can break screens | delete broad controller fields after Phase 3/6 split completion | Confirmed from code |
| Shared cache | `SharedFolderCacheRepository` + controller mirrors | `SharedCacheCatalog` | controller mirrors + repository reads | files/discovery read catalog queries | repository mutates DB/JSON and controller mirrors refresh | catalog is single writer through narrow stores | `SharedCacheCatalogBridge` | explorer and discovery read from catalog only | stale index or metadata mismatch | delete `_ownerSharedCaches`, `_ownerIndexEntriesByCacheId`, bridge after Phase 5 | Confirmed from code |
| Clipboard/history | repository + controller mirror | `ClipboardHistoryStore` | `ClipboardSheet` reads controller | UI reads history store | repository insert/trim plus controller mirror | history store writes via repository port | `ClipboardHistoryAdapter` | `ClipboardSheet` no longer needs `DiscoveryController` history surface | temporary mismatch between local history and remote projection | delete `_clipboardHistory` after Phase 6 | Confirmed from code |
| Protocol handlers | `LanDiscoveryService` | transport adapter + codecs + handlers | controller reacts to service outputs | application owners react to handler events | service send/decode methods | handlers and transport ports | `ProtocolDispatchFacade` | no scenario directly depends on mega-service packet dispatch | packet compatibility regressions | delete facade after Phase 4 compatibility suite passes | Confirmed from code |
| Files feature | `part` graph + discovery callbacks | `Files feature state owner` + `Preview cache owner` | widget tree and shared private namespace | widgets read explicit feature owner | hidden state changes in page/part/private static cache | writes through explicit feature owner and preview owner | `FileExplorerFacade` | no `part`-shared ownership remains | UI behavior drift in explorer/viewer | delete `part`-based ownership and static preview cache after Phase 6 | Confirmed from code |
| Transfer/session ownership | controller callbacks + protocol service + transfer services | `TransferSessionCoordinator` | discovery UI and services consult mixed sources | UI and services consult coordinator | controller + services advance session implicitly | coordinator advances session, services execute commands only | `TransferSessionBridge` | inbound/outbound transfer flow uses coordinator end-to-end | transfer interruption/resume bugs | delete bridge after Phase 6 session continuity tests pass | Strong inference from code structure |

### Bridge rules

#### `DeviceIdentityBridge`

- Phase introduced:
  - Phase 3
- Max allowed lifetime:
  - through Phase 3 only
- Exact deletion phase:
  - end of Phase 3
- Forbidden long-term use:
  - cannot become permanent alias layer that still lets `DiscoveryController` own identity truth

#### `PeerVocabularyAdapter`

- Phase introduced:
  - Phase 1
- Max allowed lifetime:
  - through Phase 3 only
- Exact deletion phase:
  - end of Phase 3
- Forbidden long-term use:
  - cannot remain as a “unified peer” facade over trust and friend data

#### `LegacyDiscoveryFacade`

- Phase introduced:
  - Phase 3
- Max allowed lifetime:
  - through Phase 6 only
- Exact deletion phase:
  - end of Phase 6
- Forbidden long-term use:
  - cannot become replacement mega-controller

#### `SharedCacheCatalogBridge`

- Phase introduced:
  - Phase 5
- Max allowed lifetime:
  - through Phase 5 only
- Exact deletion phase:
  - end of Phase 5
- Forbidden long-term use:
  - cannot mask controller mirrors behind a new facade

#### `ClipboardHistoryAdapter`

- Phase introduced:
  - Phase 6
- Max allowed lifetime:
  - through Phase 6 only
- Exact deletion phase:
  - end of Phase 6
- Forbidden long-term use:
  - cannot preserve `ClipboardSheet -> DiscoveryController` dependency

#### `ProtocolDispatchFacade`

- Phase introduced:
  - Phase 4
- Max allowed lifetime:
  - through Phase 4 only
- Exact deletion phase:
  - end of Phase 4
- Forbidden long-term use:
  - cannot leave transport/protocol/handlers merged behind a renamed shell

#### `FileExplorerFacade`

- Phase introduced:
  - Phase 6
- Max allowed lifetime:
  - through Phase 6 only
- Exact deletion phase:
  - end of Phase 6
- Forbidden long-term use:
  - cannot preserve part-based ownership through wrapper APIs

#### `TransferSessionBridge`

- Phase introduced:
  - Phase 6
- Max allowed lifetime:
  - through Phase 6 only
- Exact deletion phase:
  - end of Phase 6
- Forbidden long-term use:
  - cannot leave session ownership split between controller and coordinator

## 10. Phased Refactor Plan

### Phase 0: Contract lock and safety gate creation

- Goal:
  - Freeze current persistence/protocol contracts and install tests before ownership changes.
- Problems addressed:
  - unguarded migration risk
- Preconditions:
  - audit findings accepted
- Required test gate:
  - repository contract tests
  - protocol compatibility tests
  - identity mapping tests
- Concrete migration actions:
  - codify current table and packet contracts in tests
  - mark existing compatibility anchors as non-negotiable during early phases
- Temporary compatibility layer:
  - none
- What must not be done:
  - no structural refactor before tests exist
  - no renaming that hides current ownership
- Completion criteria:
  - baseline tests capture current storage and packet semantics
- What becomes deletable after this phase:
  - nothing
- Dependencies for next phase:
  - passing contract suite

### Phase 1: Identity and vocabulary split

- Goal:
  - separate local peer identity, internet endpoint records and LAN trust terminology/ownership
- Problems addressed:
  - trust vs friend conflict
  - local identity stored under wrong repository authority
- Preconditions:
  - Phase 0 test suite green
- Required test gate:
  - identity mapping tests
  - repository contract tests for `friends`, `app_settings`, `known_devices`
- Concrete migration actions:
  - introduce `LocalPeerIdentityStore`, `InternetPeerEndpointStore`, vocabulary reset
  - define read-only adapters over legacy stores
  - stop adding new uses of “friend” as a generic peer term
- Temporary compatibility layer:
  - `PeerVocabularyAdapter`
  - phase introduced: Phase 1
  - max allowed lifetime: through Phase 3
  - exact deletion phase: end of Phase 3
  - forbidden long-term use: cannot stay as permanent merged peer model
- What must not be done:
  - no dual-write between `FriendRepository` and new local identity store
  - no implicit mapping from trust to friend
- Completion criteria:
  - `FriendRepository` no longer owns conceptual local identity contract
  - all new reads distinguish trusted LAN peer vs internet endpoint vs local peer
- What becomes deletable after this phase:
  - nothing yet; only authority is narrowed
- Dependencies for next phase:
  - explicit identity owner contracts

### Phase 2: Composition root extraction from `DiscoveryPage`

- Goal:
  - remove dependency graph construction from UI lifecycle
- Problems addressed:
  - composition root in widget
- Preconditions:
  - Phase 1 ownership vocabulary in place
- Required test gate:
  - UI integration smoke tests
- Concrete migration actions:
  - move `AppDatabase.instance` / repository / service / controller assembly above `DiscoveryPage`
  - keep screen as consumer of injected boundaries only
- Temporary compatibility layer:
  - minimal injection adapter if needed
  - phase introduced: Phase 2
  - max allowed lifetime: through Phase 2
  - exact deletion phase: end of Phase 2
  - forbidden long-term use: cannot become hidden service locator in widget tree
- What must not be done:
  - no singleton sprawl
  - no new widget-owned dependency construction
- Completion criteria:
  - `DiscoveryPage` stops constructing `DiscoveryController` and low-level dependencies
- What becomes deletable after this phase:
  - dependency assembly inside `DiscoveryPage`
- Dependencies for next phase:
  - screen now consumes injected application boundary

### Phase 3: `DiscoveryController` ownership split

- Goal:
  - remove broad state ownership from `DiscoveryController`
- Problems addressed:
  - god-controller
  - mixed truth ownership for device/trust/discovery runtime
- Preconditions:
  - Phase 2 complete
- Required test gate:
  - migration regression tests
  - identity mapping tests
  - UI smoke tests
- Concrete migration actions:
  - introduce `DeviceRegistry`, `TrustedLanPeerStore`, `Discovery read/application model`
  - reroute discovery UI reads to new read model
  - keep `LegacyDiscoveryFacade` only as transition shim
- Temporary compatibility layer:
  - `LegacyDiscoveryFacade`
  - phase introduced: Phase 3
  - max allowed lifetime: through Phase 6
  - exact deletion phase: end of Phase 6
  - forbidden long-term use: cannot absorb more responsibilities
- What must not be done:
  - no `BaseManager`
  - no splitting one controller into several files without changing write authority
  - no new direct repository writes from widgets
- Completion criteria:
  - device/trust writes no longer go through `DiscoveryController`
  - discovery UI reads explicit projection instead of broad controller maps
- What becomes deletable after this phase:
  - `_devicesByIp` as identity truth
  - `_aliasByMac`
  - `_trustedDeviceMacs` as primary store
- Dependencies for next phase:
  - handler split in protocol layer now has explicit owners to target

### Phase 4: `LanDiscoveryService` transport/protocol/codecs/handler split

- Goal:
  - separate wire semantics from scenario dispatch and application reactions
- Problems addressed:
  - protocol mega-service
- Preconditions:
  - explicit owners exist for identity/discovery reads
- Required test gate:
  - protocol compatibility tests
  - session continuity tests
- Concrete migration actions:
  - isolate transport adapter
  - isolate packet codecs
  - isolate scenario handlers for discovery/friend/share/clipboard/transfer
  - route handler outputs to application owners instead of controller monolith
- Temporary compatibility layer:
  - `ProtocolDispatchFacade`
  - phase introduced: Phase 4
  - max allowed lifetime: through Phase 4
  - exact deletion phase: end of Phase 4
  - forbidden long-term use: cannot remain as renamed mega-service
- What must not be done:
  - no facade-only split
  - no moving methods into helpers while keeping one owner
- Completion criteria:
  - transport lifecycle, codecs and scenario handlers no longer share one class authority
- What becomes deletable after this phase:
  - scenario-specific responsibility concentration in `LanDiscoveryService`
- Dependencies for next phase:
  - shared cache and transfer/browser flows can now subscribe to handler outputs cleanly

### Phase 5: Shared cache subsystem split

- Goal:
  - install single-writer ownership over shared cache metadata and index lifecycle
- Problems addressed:
  - shared cache multi-owner conflict
- Preconditions:
  - Phase 4 complete
- Required test gate:
  - shared cache consistency tests
  - repository contract tests
- Concrete migration actions:
  - introduce `SharedCacheCatalog`
  - split metadata persistence and index file access
  - reroute discovery/files reads to catalog queries
  - freeze controller mirrors into compatibility-only mode, then remove
- Temporary compatibility layer:
  - `SharedCacheCatalogBridge`
  - phase introduced: Phase 5
  - max allowed lifetime: through Phase 5
  - exact deletion phase: end of Phase 5
  - forbidden long-term use: cannot proxy old controller mirrors forever
- What must not be done:
  - no dual-write to controller mirrors and new catalog
  - no part-based cache logic move sold as refactor
- Completion criteria:
  - all cache create/update/prune/rebind writes go through catalog only
  - files/discovery reads stop depending on `_ownerSharedCaches` and `_ownerIndexEntriesByCacheId`
- What becomes deletable after this phase:
  - controller cache mirrors
  - broad repository policy/orchestration surface
- Dependencies for next phase:
  - files and clipboard extraction can now consume stable cache boundary

### Phase 6: Clipboard, history, and files extraction from discovery-owned state

- Goal:
  - finish feature isolation from discovery monolith
- Problems addressed:
  - clipboard/history/files coupled to discovery owner
  - part-based files pseudo-module
  - transfer/session ownership still implicit
- Preconditions:
  - Phases 3, 4, 5 complete
- Required test gate:
  - migration regression tests
  - UI smoke tests
  - session continuity tests
- Concrete migration actions:
  - introduce `ClipboardHistoryStore`, `RemoteShareBrowser`, `Files feature state owner`, `Preview cache owner`, `TransferSessionCoordinator`
  - reroute `ClipboardSheet` away from `DiscoveryController`
  - replace part-shared ownership in files feature with explicit owners
  - move transfer session runtime authority into coordinator
- Temporary compatibility layer:
  - `ClipboardHistoryAdapter`
  - `FileExplorerFacade`
  - `TransferSessionBridge`
  - all introduced in Phase 6
  - all max lifetime: through Phase 6 only
  - exact deletion phase: end of Phase 6
  - forbidden long-term use: cannot preserve old controller callbacks or part-based ownership
- What must not be done:
  - no new mega-coordinator
  - no state framework swap as substitute
  - no helper/extensions masking old ownership
- Completion criteria:
  - `ClipboardSheet` and files feature stop using discovery-owned truth
  - transfer session state has one owner
  - preview cache is no longer static presentation-global state
- What becomes deletable after this phase:
  - `DiscoveryController._clipboardHistory`
  - file explorer `part` ownership graph
  - `_MediaPreviewCache` as owner
  - obsolete cross-feature callbacks
  - `LegacyDiscoveryFacade`
- Dependencies for next phase:
  - none. This is the cutover completion phase for current target scope.

## 11. Test Strategy and Safety Gates

### Repository contract tests

- What it protects:
  - table semantics for `known_devices`, `shared_folder_caches`, `friends`, `app_settings`, `clipboard_history`, `transfer_history`
- Why the phase is unsafe without it:
  - ownership split can silently change persistence contract
- Critical stop-signal failure:
  - existing durable rows cannot be read back with pre-migration semantics
- Earliest required phase:
  - Phase 0

### Protocol compatibility tests

- What it protects:
  - packet identifiers and envelope semantics in `LanDiscoveryService`
- Why the phase is unsafe without it:
  - protocol split in Phase 4 can break peer interoperability
- Critical stop-signal failure:
  - previously valid packet decode/encode cases drift
- Earliest required phase:
  - Phase 0

### Session continuity tests

- What it protects:
  - transfer negotiation and runtime session ownership continuity
- Why the phase is unsafe without it:
  - session cutovers across Phase 4 and Phase 6 can orphan active flows
- Critical stop-signal failure:
  - accepted transfer cannot complete through the refactored path
- Earliest required phase:
  - Phase 4

### Identity mapping tests

- What it protects:
  - IP-to-MAC mapping rules and alias/trust continuity
- Why the phase is unsafe without it:
  - device identity split is a direct product contract
- Critical stop-signal failure:
  - alias or trust no longer follows the same MAC after IP change
- Earliest required phase:
  - Phase 0

### Shared cache consistency tests

- What it protects:
  - metadata/index alignment for shared folder cache
- Why the phase is unsafe without it:
  - Phase 5 changes single-writer ownership over two persistence forms
- Critical stop-signal failure:
  - DB row and JSON index diverge after create/update/prune/rebind
- Earliest required phase:
  - Phase 5

### UI integration smoke tests

- What it protects:
  - screen entry flows after composition root and feature extraction changes
- Why the phase is unsafe without it:
  - `DiscoveryPage`, `ClipboardSheet`, files feature entrypoints are lifecycle-heavy
- Critical stop-signal failure:
  - screen cannot open key feature flows
- Earliest required phase:
  - Phase 2

### Migration regression tests

- What it protects:
  - adapter cutovers and deletion readiness
- Why the phase is unsafe without it:
  - bridge layers can mask regressions until legacy code is deleted
- Critical stop-signal failure:
  - old and new read paths diverge before cutover
- Earliest required phase:
  - Phase 3

Evidence level: Confirmed from code  
Source of truth: current existing tests are limited to `test/app_settings_repository_test.dart`, `test/clipboard_history_repository_test.dart`, `test/video_link_share_service_test.dart`, `test/smoke_test.dart`; missing suites above are not present in current `test/`

## 12. Data, Storage and Protocol Compatibility

### Persistence anchors that must remain stable during early phases

- `known_devices`
- `shared_folder_caches`
- `transfer_history`
- `app_settings`
- `friends`
- `clipboard_history`
- shared cache JSON index files under the shared cache directory

Evidence level: Confirmed from code  
Source of truth: `lib/core/storage/app_database.dart` / `knownDevicesTable`, `sharedFolderCachesTable`, `transferHistoryTable`, `appSettingsTable`, `friendsTable`, `clipboardHistoryTable`; `lib/features/transfer/data/shared_folder_cache_repository.dart` / JSON index read/write methods

### Compatibility rules

- What must remain stable:
  - normalized MAC handling for device identity persistence
  - existing rows in SQLite tables above
  - existing JSON index file schema usage as readable cache artifact
  - current UDP packet identifiers such as `LANDA_DISCOVER_V1`, `LANDA_HERE_V1`, `LANDA_TRANSFER_REQUEST_V1`, `LANDA_CLIPBOARD_CATALOG_V1`
- What may migrate lazily:
  - internal read paths from controller mirrors to explicit stores
  - UI projections
- What needs explicit migration:
  - `local_peer_id` ownership
  - shared cache write authority
  - transfer/session runtime authority
- Where dual-read is allowed:
  - Phase 1 for `local_peer_id`
  - Phase 5 for shared cache reads
  - Phase 6 for clipboard/files/session read cutover
- Where dual-write is forbidden:
  - settings vs local peer identity
  - trust vs friend records
  - shared cache metadata/index/controller mirror ownership
  - session ownership between controller and coordinator
- Wire semantics that must not drift:
  - packet identifiers
  - envelope semantics used in `LanDiscoveryService`
  - self-identification behavior implied by current discovery packet constants and send/decode methods

Evidence level: Confirmed from code  
Source of truth: `lib/features/discovery/data/lan_discovery_service.dart` / packet constants and send/decode methods; `lib/features/discovery/data/device_alias_repository.dart` / `normalizeMac`; `lib/features/discovery/data/friend_repository.dart` / `_localPeerIdKey`

Missing artifact:
- Cross-version peer interoperability evidence outside current Dart runtime.

Impact of uncertainty:
- Exact backward-compat matrix with already-installed peers cannot be fully proven from current audit alone.

Safest interim assumption:
- Treat every existing packet identifier and envelope shape visible in Dart as frozen until dedicated compatibility tests prove otherwise.

## 13. Event and Side-Effect Discipline

### Discovery

- Events published:
  - device seen
  - trust changed
  - discovery projection changed
- Publisher:
  - protocol handler / `DeviceRegistry` / `TrustedLanPeerStore`
- Consumers:
  - discovery read model
- Allowed side effects:
  - persistence updates through owner ports
- Forbidden side effects:
  - widget-triggered direct DB or network writes
- Idempotency requirement:
  - repeated device seen events must not duplicate identity rows
- Dedupe requirement:
  - same device observation must collapse by stable identity key
- Current event-spaghetti source:
  - controller both receives and mutates discovery state directly
- Target control point:
  - dedicated owners plus read model
- Evidence level:
  - Strong inference from code structure

### Clipboard

- Events published:
  - clipboard captured
  - remote clipboard catalog received
  - history changed
- Publisher:
  - clipboard capture service, protocol clipboard handler, `ClipboardHistoryStore`
- Consumers:
  - clipboard UI, optional discovery read model
- Allowed side effects:
  - durable history write via `ClipboardHistoryStore`
- Forbidden side effects:
  - `ClipboardSheet` mutating durable history directly
- Idempotency requirement:
  - repeated local captures must dedupe by content/hash policy
- Dedupe requirement:
  - remote clipboard duplicates must not fan out into multiple local entries
- Current event-spaghetti source:
  - controller owns both remote protocol reaction and local history mirror
- Target control point:
  - history store for local durable state, remote browser/session owner for remote projection
- Evidence level:
  - Confirmed from code
- Source of truth:
  - `lib/features/discovery/application/discovery_controller.dart` / `_handleClipboardQuery`, `_onClipboardCatalog`, `_clipboardHistory`
  - `lib/features/clipboard/data/clipboard_history_repository.dart` / `hasHash`, `insert`

### Transfer negotiation

- Events published:
  - transfer requested
  - transfer accepted/rejected
  - transfer progressed/completed/failed
- Publisher:
  - protocol handlers and `TransferSessionCoordinator`
- Consumers:
  - transfer UI, history persistence port
- Allowed side effects:
  - transport send through transport/handler boundary
  - storage writes through execution service
- Forbidden side effects:
  - widgets driving session state directly
- Idempotency requirement:
  - duplicate inbound request packets must not open duplicate sessions
- Dedupe requirement:
  - session identity must collapse repeated events into one session
- Current event-spaghetti source:
  - transfer callbacks split across controller, discovery service and transfer service
- Target control point:
  - `TransferSessionCoordinator`
- Evidence level:
  - Strong inference from code structure

### Share catalog refresh

- Events published:
  - remote share catalog received
  - shared cache updated
- Publisher:
  - share handler, `SharedCacheCatalog`
- Consumers:
  - `RemoteShareBrowser`, files owner, discovery read model
- Allowed side effects:
  - receiver cache persistence through catalog owner
- Forbidden side effects:
  - direct controller mirror mutation after cutover
- Idempotency requirement:
  - repeated same catalog packet must not fork duplicate cache entries
- Dedupe requirement:
  - receiver cache update must collapse by cache identity
- Current event-spaghetti source:
  - controller reacts to catalog, repository persists, UI reads mirrors
- Target control point:
  - `SharedCacheCatalog` + `RemoteShareBrowser`
- Evidence level:
  - Confirmed from code
- Source of truth:
  - `lib/features/discovery/application/discovery_controller.dart` / `_handleShareCatalog`
  - `lib/features/transfer/data/shared_folder_cache_repository.dart` / `saveReceiverCache`

### Preview generation

- Events published:
  - preview requested
  - preview ready
  - preview invalidated
- Publisher:
  - files owner / preview cache owner
- Consumers:
  - explorer/viewer UI
- Allowed side effects:
  - preview file generation/cleanup through preview cache owner
- Forbidden side effects:
  - widgets writing preview artifacts directly
- Idempotency requirement:
  - same file key must reuse existing valid preview
- Dedupe requirement:
  - repeated concurrent requests must converge on one preview artifact
- Current event-spaghetti source:
  - static preview cache hidden in part-based presentation module
- Target control point:
  - `Preview cache owner`
- Evidence level:
  - Confirmed from code
- Source of truth:
  - `lib/features/files/presentation/file_explorer/media_preview_cache.dart` / `_MediaPreviewCache`

### Notifications

- Events published:
  - transfer/download completion related notifications or publish effects
- Publisher:
  - platform-aware storage/transfer side-effect collaborators
- Consumers:
  - platform notification layer only
- Allowed side effects:
  - external user notification after committed domain event
- Forbidden side effects:
  - notifications emitted from widgets or before domain action commits
- Idempotency requirement:
  - repeated same completion event must not spam notifications
- Dedupe requirement:
  - notifications keyed by transfer/session identity
- Current event-spaghetti source:
  - side effects live in broad service/controller flows instead of committed event boundary
- Target control point:
  - post-commit side-effect adapter behind transfer/session owner
- Evidence level:
  - Strong inference from code structure

Missing artifact:
- exact notification orchestration path outside visible Dart call sites

Impact of uncertainty:
- final adapter split may need platform-specific confirmation.

Safest interim assumption:
- notifications must remain post-commit side effects and never regain write authority over domain state.

## 14. Fake Refactors to Reject

### `part / part of`

- Why it looks attractive:
  - fast file split without changing code references
- Why it fails technically:
  - ownership remains one shared private namespace
- What it preserves:
  - hidden coupling and implicit state sharing
- Which current repo artifact it would only rename:
  - `lib/features/files/presentation/file_explorer_page.dart` and its `part` graph

### Extensions instead of ownership split

- Why it looks attractive:
  - large class gets shorter
- Why it fails technically:
  - the same object still owns the same state and side effects
- What it preserves:
  - god-controller/god-service authority
- Which current repo artifact it would only rename:
  - `DiscoveryController`, `LanDiscoveryService`

### Helpers instead of decomposition

- Why it looks attractive:
  - moves logic out of main file quickly
- Why it fails technically:
  - write authority and lifecycle ownership do not change
- What it preserves:
  - architectural ambiguity
- Which current repo artifact it would only rename:
  - `SharedFolderCacheRepository`, `TransferStorageService`

### Facade without real transport/protocol/handler split

- Why it looks attractive:
  - surface gets cleaner while internal mass stays untouched
- Why it fails technically:
  - one service still owns transport, codecs and scenario dispatch
- What it preserves:
  - wire-risk concentration
- Which current repo artifact it would only rename:
  - `LanDiscoveryService`

### New mega-coordinator

- Why it looks attractive:
  - promises central orchestration
- Why it fails technically:
  - replaces one god-object with another
- What it preserves:
  - cross-domain write monopoly
- Which current repo artifact it would only rename:
  - `DiscoveryController`

### State framework replacement without ownership reset

- Why it looks attractive:
  - tooling appears modern
- Why it fails technically:
  - same ownership chaos survives in a new API shape
- What it preserves:
  - wrong boundaries
- Which current repo artifact it would only rename:
  - `DiscoveryController` plus feature flows around it

### Moving logic into more files without new write authority boundaries

- Why it looks attractive:
  - diff looks large and “architectural”
- Why it fails technically:
  - state seams remain open and writes stay uncontrolled
- What it preserves:
  - multi-owner truth conflicts
- Which current repo artifact it would only rename:
  - files module and discovery module

### Long-lived cross-feature callbacks sold as modularity

- Why it looks attractive:
  - avoids explicit contracts
- Why it fails technically:
  - keeps hidden backchannels between features
- What it preserves:
  - UI-driven application coupling
- Which current repo artifact it would only rename:
  - `DiscoveryPage` feature launch callbacks and `ClipboardSheet` controller coupling

## 15. Deletion Map

| Artifact | Phase deletable | Deletion condition | Evidence proving safe deletion |
| --- | --- | --- | --- |
| `DiscoveryPage` dependency assembly (`AppDatabase.instance`, repository/service/controller construction) | Phase 2 | screen receives injected boundary only | no constructor graph remains in `DiscoveryPage`; smoke tests pass |
| `FriendRepository` conceptual ownership of `_localPeerIdKey` | Phase 1 | local peer identity writes route only through `LocalPeerIdentityStore` | repository contract tests show identity path no longer depends on friend repo authority |
| `DiscoveryController._devicesByIp` as identity truth | Phase 3 | discovery read path uses `DeviceRegistry` | identity mapping tests pass under IP change scenarios |
| `DiscoveryController._aliasByMac` primary ownership | Phase 3 | alias reads come from device/trust stores | registry-driven projection matches legacy behavior |
| `DiscoveryController._trustedDeviceMacs` primary ownership | Phase 3 | trust writes/reads route via `TrustedLanPeerStore` | trust tests and UI smoke tests pass |
| `ProtocolDispatchFacade` | Phase 4 | all packet flows go through transport/codecs/handlers without facade | protocol compatibility tests pass |
| `DiscoveryController._ownerSharedCaches` | Phase 5 | discovery/files read shared cache catalog only | shared cache consistency tests and migration regression tests pass |
| `DiscoveryController._ownerIndexEntriesByCacheId` | Phase 5 | index reads come from `SharedCacheCatalog` | explorer reads stay correct without controller mirror |
| `SharedCacheCatalogBridge` | Phase 5 | catalog is sole write authority | no direct controller mirror refresh remains |
| `DiscoveryController._clipboardHistory` | Phase 6 | clipboard UI reads `ClipboardHistoryStore` | `ClipboardSheet` no longer references controller history surface |
| `ClipboardHistoryAdapter` | Phase 6 | clipboard/history cutover complete | migration regression tests pass |
| Files feature `part` ownership graph | Phase 6 | explicit files owner and preview owner exist | no `part / part of` used for feature-wide ownership |
| `_MediaPreviewCache` as owner | Phase 6 | preview lifecycle managed by explicit owner | preview requests and cleanup route through owner only |
| obsolete cross-feature callbacks from discovery UI | Phase 6 | features consume explicit boundaries instead of ad-hoc callbacks | UI smoke tests pass with injected feature contracts |
| `LegacyDiscoveryFacade` | Phase 6 | no screen depends on broad legacy controller surface | all feature flows use explicit owners/read models |
| `TransferSessionBridge` | Phase 6 | transfer session coordinator owns runtime session state end-to-end | session continuity tests pass |

## 16. Final Verdict

Проект реально оздоровим без полного rewrite. Но это верно только при одном условии: рефактор пойдёт по ownership seams, а не по размерам файлов и не по модным абстракциям. Текущий structural debt уже опасен в discovery/shared-cache/protocol/files. Дальше наращивать функциональность поверх `DiscoveryController`, `DiscoveryPage`, `LanDiscoveryService` и `SharedFolderCacheRepository` нельзя без роста регрессионного радиуса.

Где incremental refactor реален:
- identity and vocabulary split
- composition root extraction
- shared cache single-writer installation
- clipboard/files extraction after ownership stabilization

Где долг остаётся опасным даже после успешной миграции:
- protocol interoperability с уже существующими peers без отдельной compatibility matrix
- platform-specific storage/notification semantics вне Dart audit
- video share subsystem, если его HTTP/session/html responsibilities останутся в одном классе дольше необходимого

Топ шагов с максимальным эффектом:
- Phase 1: вытащить local peer identity из friend ownership и развести trust vs internet peer
- Phase 2: убрать composition root из `DiscoveryPage`
- Phase 3: разрезать `DiscoveryController` по реальным owners
- Phase 4: вынести transport/codecs/handlers из `LanDiscoveryService`
- Phase 5: поставить single-writer ownership на shared cache

Обязательные шаги:
- Phase 0
- Phase 1
- Phase 2
- Phase 3
- Phase 4
- Phase 5
- Phase 6

Вторичные шаги:
- дополнительная декомпозиция `VideoLinkShareService`
- дополнительная декомпозиция `TransferStorageService` после стабилизации основного ownership refactor-а

Остающиеся риски после успешной миграции:
- если bridge layers переживут свой deletion phase, рефактор провален
- если dual-write будет допущен в identity/shared-cache/session flows, консистентность снова расползётся
- если discovery read model превратится в новый mega-controller, проект просто поменяет название старой проблемы

Evidence level: Strong inference from code structure  
Source of truth: итог основан на совокупности подтверждённых проблем в `lib/features/discovery/application/discovery_controller.dart`, `lib/features/discovery/presentation/discovery_page.dart`, `lib/features/discovery/data/lan_discovery_service.dart`, `lib/features/transfer/data/shared_folder_cache_repository.dart`, `lib/features/files/presentation/file_explorer_page.dart`

Missing artifact:
- Полная cross-platform compatibility matrix и реальный runtime behavior вне Dart boundary.

Impact of uncertainty:
- Некоторые later-stage adapter decisions могут потребовать корректировки по platform-specific ограничениям.

Safest interim assumption:
- Не менять persistence и wire contracts раньше, чем это будет покрыто отдельными compatibility tests и платформенной валидацией.
