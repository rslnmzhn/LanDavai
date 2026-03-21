# Refactor Workpacks Index

## 1. Purpose

Это набор тактических workpacks, производных от `docs/refactor_master_plan.md`. Он не заменяет master plan и не вводит новую архитектуру. Его задача: разложить утверждённый стратегический план на узкие, исполнимые migration slices, которые можно брать в работу по одному.

## 2. How to use

- Читать сначала `docs/refactor_master_plan.md`, потом этот index.
- Брать workpacks только в dependency order.
- Не начинать workpack, если его `Required test gate` не установлен и не зелёный.
- Не перепрыгивать через workpacks, которые переключают write authority или закрывают bridge lifetime.
- `Derived planning helper` не трактовать как новую архитектурную сущность.
- Если workpack использует явный uncertainty block, это не ослабляет ownership rules, а только фиксирует честную границу аудита.

## 3. Workpack registry

| Workpack ID | Title | Master phase | Primary seam | Legacy owner unloaded | Target owner activated | Bridge used | Required test gate | Completion proof | Blocks deletion of |
| --- | --- | --- | --- | --- | --- | --- | --- | --- | --- |
| 00 | Index | All | execution map | none | none | none | none | registry, dependencies, and waves are consistent | orphaned sequencing |
| 01 | Phase 0 contract lock | Phase 0 | compatibility fence | none | none | none | none | canonical `GATE-*` matrix exists and anchors are frozen | all later deletions |
| 02 | Phase 1 local peer identity and vocabulary baseline | Phase 1 | local identity vs friend semantics | `FriendRepository` conceptual local-identity ownership | `LocalPeerIdentityStore` | `PeerVocabularyAdapter` | `GATE-01`, `GATE-03` | local identity no longer owned by `FriendRepository` | deletion of `_localPeerIdKey` ownership |
| 03a | Phase 1 internet peer endpoint store activation | Phase 1 | internet endpoint ownership | `FriendRepository` as business owner of endpoint records | `InternetPeerEndpointStore` | `PeerVocabularyAdapter` | `GATE-01`, `GATE-07` | endpoint writes route only through the store | deletion of `_friends` as business truth |
| 03b | Phase 1 settings store activation | Phase 1 | app settings ownership | controller and unrelated repositories writing `app_settings` as business owners | `SettingsStore` | none | `GATE-01` | settings writes route only through the store | deletion of `_loadSettings`, `_saveSettings` |
| 03 | Phase 2 discovery page composition root extraction | Phase 2 | UI lifecycle vs dependency lifecycle | `DiscoveryPage` assembly logic | app-level composition root | none | `GATE-06` | `DiscoveryPage` stops constructing graph | deletion of page-side assembly |
| 04 | Phase 3 device registry split | Phase 3 | device identity ownership | `DiscoveryController` identity writes | `DeviceRegistry` | `DeviceIdentityBridge` | `GATE-01`, `GATE-03`, `GATE-07` | registry is sole identity writer | deletion of `_devicesByIp` and `_aliasByMac` as truths |
| 05 | Phase 3 trusted LAN peer store split | Phase 3 | trust write authority | `DiscoveryController` and implicit repo-owned trust flow | `TrustedLanPeerStore` | none | `GATE-01`, `GATE-03` | trust writes bypass controller | deletion of `_trustedDeviceMacs` as truth |
| 06 | Phase 3 discovery read/application model cutover | Phase 3 | discovery UI read path | direct widget reads from `DiscoveryController` | `Discovery read/application model` | `LegacyDiscoveryFacade` | `GATE-06`, `GATE-07` | widgets stop reading controller truth directly | deletion of broad discovery read surface |
| 20 | Phase 3 discovery controller legacy field and method downgrade | Phase 3 | controller legacy truth retirement | legacy controller fields and settings methods | no new owner; phase 1 and 3 owners remain | `PeerVocabularyAdapter`, `DeviceIdentityBridge` | `GATE-01`, `GATE-03`, `GATE-06`, `GATE-07` | no downgraded controller artifact remains a writer | deletion of `_devicesByIp`, `_aliasByMac`, `_trustedDeviceMacs`, `_friends`, `_loadSettings`, `_saveSettings` |
| 07 | Phase 4 transport adapter extraction | Phase 4 | socket lifecycle ownership | `LanDiscoveryService` transport internals | transport adapter | `ProtocolDispatchFacade` | `GATE-02` | UDP lifecycle leaves `LanDiscoveryService` | facade deletion |
| 08 | Phase 4 packet codec split | Phase 4 | packet codec ownership | `LanDiscoveryService` codec methods | packet codec set | `ProtocolDispatchFacade` | `GATE-02` | codec parity proven | facade deletion |
| 09 | Phase 4 protocol handlers split | Phase 4 | scenario dispatch ownership | `LanDiscoveryService` scenario dispatch | handler families by scenario | `ProtocolDispatchFacade` | `GATE-02`, `GATE-04` | handler-family staged split complete | facade deletion |
| 21 | Phase 4 protocol dispatch facade removal | Phase 4 | bridge lifetime closure | `ProtocolDispatchFacade` | no new owner | `ProtocolDispatchFacade` | `GATE-02`, `GATE-04` | no call path depends on facade | facade deletion |
| 10 | Phase 5 shared cache metadata owner | Phase 5 | cache metadata write ownership | broad `SharedFolderCacheRepository` metadata authority | `SharedCacheCatalog` | `SharedCacheCatalogBridge` | `GATE-01`, `GATE-05` | catalog owns metadata writes | mirror and read cutovers |
| 11 | Phase 5 shared cache index store split | Phase 5 | JSON index ownership | `SharedFolderCacheRepository` index IO | index file store | `SharedCacheCatalogBridge` | `GATE-05` | index writes isolated | mirror and read cutovers |
| 22 | Phase 5 shared cache read cutover | Phase 5 | files and discovery cache reads | controller mirrors and direct repository reads | no new owner; catalog read API becomes canonical | `SharedCacheCatalogBridge` | `GATE-05`, `GATE-06`, `GATE-07` | files and discovery read catalog only | mirror removal |
| 12 | Phase 5 controller cache mirror removal | Phase 5 | controller cache mirrors | `DiscoveryController` cache mirrors | no new owner; `SharedCacheCatalog` remains canonical | `SharedCacheCatalogBridge` | `GATE-05`, `GATE-06`, `GATE-07` | no mirror reads or writes remain | deletion of `_ownerSharedCaches`, `_ownerIndexEntriesByCacheId`, bridge |
| 13 | Phase 6 clipboard history extraction | Phase 6 | local clipboard durable state | `DiscoveryController` history mirror | `ClipboardHistoryStore` | `ClipboardHistoryAdapter` | `GATE-01`, `GATE-06`, `GATE-07` | local clipboard history leaves controller | deletion of `_clipboardHistory` |
| 13a | Phase 6 remote clipboard projection extraction | Phase 6 | remote clipboard session projection | `DiscoveryController` remote clipboard projection | remote clipboard projection boundary | `LegacyDiscoveryFacade` | `GATE-02`, `GATE-06`, `GATE-07` | `ClipboardSheet` stops reading remote projection from controller | deletion of remote clipboard half of `ClipboardSheet -> DiscoveryController` |
| 14 | Phase 6 remote share browser extraction | Phase 6 | remote share browse session | `DiscoveryController._remoteShareOptions` | `RemoteShareBrowser` | `LegacyDiscoveryFacade` | `GATE-02`, `GATE-05`, `GATE-06`, `GATE-07` | browse session leaves discovery controller | deletion of `_remoteShareOptions` |
| 15 | Phase 6 files feature state owner split | Phase 6 | explorer navigation and view state | `file_explorer_*` part-owned state | `Files feature state owner` | `FileExplorerFacade` | `GATE-06`, `GATE-07` | files UI reads explicit owner | deletion of part-owned state cluster |
| 16 | Phase 6 preview cache owner split | Phase 6 | preview lifecycle | `_MediaPreviewCache` | `Preview cache owner` | `FileExplorerFacade` | `GATE-06`, `GATE-07` | preview lifecycle leaves static cache | deletion of `_MediaPreviewCache` |
| 17 | Phase 6 transfer session coordinator split | Phase 6 | transfer session ownership | controller, protocol, and service mixed session state | `TransferSessionCoordinator` | `TransferSessionBridge` | `GATE-02`, `GATE-04`, `GATE-07` | coordinator is sole transfer-session writer | deletion of implicit session flows and bridge |
| 13b | Phase 6 download history extraction | Phase 6 | discovery-owned download history | `DiscoveryController._downloadHistory` | download history boundary | `LegacyDiscoveryFacade` | `GATE-06`, `GATE-07` | download history leaves discovery controller | deletion of `_downloadHistory` |
| 23 | Phase 6 obsolete cross-feature callbacks removal | Phase 6 | callback backchannels and lingering facades | callback lattice, `LegacyDiscoveryFacade`, `FileExplorerFacade` | no new owner; explicit feature contracts remain | legacy callback compatibility surfaces | `GATE-06`, `GATE-07` | no foreign seam is reachable through callback or facade | deletion of callbacks and facades |
| 18 | Deletion wave map | All | deletion coordination | none | none | none | all listed owning workpack proofs | every legacy artifact has an owner, proof, and blocker chain | orphaned legacy code |
| 19 | Test gates matrix | All | gate coordination | none | none | none | none | canonical gate matrix matches every workpack precondition | unsafe sequencing |

## 4. Dependency graph

- `01 -> 02`
- `01 + 02 -> 03a`
- `01 + 02 -> 03b`
- `01 + 02 -> 03`
- `03 -> 04`
- `03 -> 05`
- `03a + 04 + 05 -> 06`
- `03a + 03b + 04 + 05 + 06 -> 20`
- `01 + 06 -> 07`
- `01 + 06 -> 08`
- `07 + 08 -> 09`
- `07 + 08 + 09 -> 21`
- `01 + 21 -> 10`
- `10 -> 11`
- `10 + 11 + 21 -> 22`
- `10 + 11 + 22 -> 12`
- `01 + 06 -> 13`
- `06 + 09 -> 13a`
- `06 + 09 + 12 + 22 -> 14`
- `12 + 14 -> 15`
- `15 -> 16`
- `06 + 21 -> 17`
- `06 + 17 -> 13b`
- `06 + 13 + 13a + 13b + 14 + 15 + 16 + 17 -> 23`
- `all executable workpacks -> 18`
- `19` must stay synchronized with every workpack above

## 5. Parallelism rules

Можно параллелить:
- `03a` и `03b` после завершения `02`
- `04` и `05` после завершения `03`
- `07` и `08` после завершения `06`
- `13` и `13a` после завершения их собственных зависимостей

Нельзя параллелить:
- `06` с `03a`, `04`, `05`, потому что read model должен опираться на уже активированные owners
- `12` с `22`, потому что mirror removal без read cutover ломает files and discovery reads
- `15` с `14`, потому что files owner должен читать уже вынесенный remote browse state
- `17` с `21`, потому что transfer session ownership не должен строиться поверх незакрытого protocol facade
- `13b` с `17`, потому что history boundary зависит от уже стабилизированного transfer-session owner
- `23` раньше завершения `06`, `13`, `13a`, `13b`, `14`, `15`, `16`, `17`, иначе удаление callback surfaces останется без replacement contracts

## 6. Deletion waves

- Wave A:
  - `02`, `03a`, `03b`, `03`
  - unlocks: conceptual ownership of `_localPeerIdKey`, preparation for `_friends`, `_loadSettings`, `_saveSettings`, page-side composition root
- Wave B:
  - `04`, `05`, `06`, `20`
  - unlocks: `_devicesByIp`, `_aliasByMac`, `_trustedDeviceMacs`, `_friends`, `_loadSettings`, `_saveSettings`, `PeerVocabularyAdapter`, `DeviceIdentityBridge`
- Wave C:
  - `07`, `08`, `09`, `21`
  - unlocks: `ProtocolDispatchFacade` and residual protocol mega-service routing shell
- Wave D:
  - `10`, `11`, `22`, `12`
  - unlocks: `_ownerSharedCaches`, `_ownerIndexEntriesByCacheId`, `SharedCacheCatalogBridge`
- Wave E:
  - `13`, `13a`, `14`, `15`, `16`, `17`, `13b`, `23`
  - unlocks: `_clipboardHistory`, `ClipboardSheet -> DiscoveryController`, `_remoteShareOptions`, `_MediaPreviewCache`, `TransferSessionBridge`, `_downloadHistory`, `LegacyDiscoveryFacade`, `FileExplorerFacade`, obsolete cross-feature callbacks
