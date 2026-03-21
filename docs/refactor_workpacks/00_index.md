# Refactor Workpacks Index

## 1. Purpose

Это набор тактических workpacks, производных от `docs/refactor_master_plan.md`. Он не заменяет master plan и не вводит новую архитектуру. Его задача: разложить утверждённый стратегический план на узкие, исполнимые migration slices, которые можно брать в работу по одному.

## 2. How to use

- Читать сначала `docs/refactor_master_plan.md`, потом этот index.
- Брать workpacks только в dependency order.
- Не начинать workpack, если его `Required test gate` не установлен.
- Не перепрыгивать через workpacks, которые переключают write authority или закрывают bridge lifetime.
- Не трактовать `Derived planning helper` как новую архитектурную сущность.

## 3. Workpack registry

| Workpack ID | Title | Master phase | Primary seam | Legacy owner unloaded | Target owner activated | Bridge used | Required test gate | Completion proof | Blocks deletion of |
| --- | --- | --- | --- | --- | --- | --- | --- | --- | --- |
| 00 | Index | All | Execution map | None | None | None | None | registry complete | nothing |
| 01 | Phase 0 contract lock | Phase 0 | compatibility fence | none | none | none | repository + protocol + identity tests | contract suite green | all later deletions |
| 02 | Phase 1 identity and vocabulary split | Phase 1 | local peer identity vs friend/settings vocabulary | `FriendRepository` conceptual ownership | `LocalPeerIdentityStore` | `PeerVocabularyAdapter` | repository contract + identity mapping | `local_peer_id` cutover contract fixed | deletion of `_localPeerIdKey` ownership |
| 03 | Phase 2 composition root extraction | Phase 2 | UI lifecycle vs dependency lifecycle | `DiscoveryPage` assembly logic | app-level composition root | none | UI smoke | `DiscoveryPage` stops constructing graph | deletion of page-side assembly |
| 04 | Phase 3 device registry split | Phase 3 | device identity ownership | `DiscoveryController` identity writes | `DeviceRegistry` | `DeviceIdentityBridge` | identity mapping + migration regression | registry is single device identity writer | deletion of `_devicesByIp` as truth |
| 05 | Phase 3 trusted LAN peer store split | Phase 3 | trust write authority | `DiscoveryController` / implicit repo-owned trust flow | `TrustedLanPeerStore` | none | repository contract + identity mapping | trust writes bypass controller | deletion of `_trustedDeviceMacs` as truth |
| 06 | Phase 3 discovery read model cutover | Phase 3 | discovery UI read path | direct widget reads from `DiscoveryController` | `Discovery read/application model` | `LegacyDiscoveryFacade` | UI smoke + migration regression | widgets stop reading controller maps | deletion of legacy discovery read surface |
| 07 | Phase 4 transport adapter extraction | Phase 4 | socket lifecycle ownership | `LanDiscoveryService` transport internals | transport adapter | `ProtocolDispatchFacade` | protocol compatibility | transport lifecycle isolated | facade deletion |
| 08 | Phase 4 packet codec split | Phase 4 | packet encode/decode ownership | `LanDiscoveryService` codec methods | packet codec set | `ProtocolDispatchFacade` | protocol compatibility | codec parity proven | facade deletion |
| 09 | Phase 4 protocol handlers split | Phase 4 | scenario dispatch ownership | `LanDiscoveryService` scenario dispatch | protocol handlers by scenario | `ProtocolDispatchFacade` | protocol compatibility + session continuity | handlers publish scenario events | facade deletion |
| 10 | Phase 5 shared cache metadata owner | Phase 5 | shared cache metadata writes | `SharedFolderCacheRepository` broad metadata authority | `SharedCacheCatalog` | `SharedCacheCatalogBridge` | repository contract + shared cache consistency | catalog owns metadata writes | mirror removal |
| 11 | Phase 5 shared cache index store split | Phase 5 | JSON index ownership | `SharedFolderCacheRepository` index IO | index file store | `SharedCacheCatalogBridge` | shared cache consistency | index writes isolated | mirror/read cutover |
| 12 | Phase 5 controller cache mirror removal | Phase 5 | controller cache mirrors | `DiscoveryController` mirror fields | no new owner; `SharedCacheCatalog` remains owner | `SharedCacheCatalogBridge` | migration regression + shared cache consistency | no mirror writes remain | deletion of `_ownerSharedCaches`, `_ownerIndexEntriesByCacheId` |
| 13 | Phase 6 clipboard history extraction | Phase 6 | local clipboard durable state | `DiscoveryController` history mirror | `ClipboardHistoryStore` | `ClipboardHistoryAdapter` | repository contract + UI smoke | `ClipboardSheet` stops reading controller history | deletion of `_clipboardHistory` |
| 14 | Phase 6 remote share browser extraction | Phase 6 | remote browse session ownership | `DiscoveryController._remoteShareOptions` | `RemoteShareBrowser` | `LegacyDiscoveryFacade` | shared cache consistency + UI smoke | browse session leaves discovery controller | deletion of `_remoteShareOptions` |
| 15 | Phase 6 files feature state owner split | Phase 6 | explorer navigation/view state | `file_explorer_*` part-owned state | `Files feature state owner` | `FileExplorerFacade` | UI smoke + migration regression | files UI reads explicit owner | deletion of part-owned state cluster |
| 16 | Phase 6 preview cache owner split | Phase 6 | preview cache lifecycle | `_MediaPreviewCache` | `Preview cache owner` | `FileExplorerFacade` | UI smoke + migration regression | preview lifecycle leaves static cache | deletion of `_MediaPreviewCache` |
| 17 | Phase 6 transfer session coordinator split | Phase 6 | transfer session ownership | controller/protocol/service mixed session state | `TransferSessionCoordinator` | `TransferSessionBridge` | session continuity + protocol compatibility | coordinator is only session writer | deletion of implicit session flows |
| 18 | Deletion wave map | All | deletion coordination | none | none | none | all related workpack proofs | deletion map complete | orphaned legacy code |
| 19 | Test gates matrix | All | test gate coordination | none | none | none | none | gate map complete | unsafe sequencing |
| 20 | Phase 3 discovery controller legacy field downgrade | Phase 3 | legacy identity/trust field downgrade | `DiscoveryController` legacy identity/trust fields | no new owner; existing phase 3 owners remain | none | identity mapping + UI smoke | fields downgraded or deleted | actual field deletion |
| 21 | Phase 4 protocol dispatch facade removal | Phase 4 | facade lifetime closure | `ProtocolDispatchFacade` | no new owner; transport/codecs/handlers remain | `ProtocolDispatchFacade` | protocol compatibility + session continuity | no call path depends on facade | facade deletion |
| 22 | Phase 5 shared cache read cutover | Phase 5 | discovery/files read path | controller mirrors + direct repository reads | no new owner; `SharedCacheCatalog` read API becomes canonical | `SharedCacheCatalogBridge` | shared cache consistency + UI smoke | files/discovery read catalog only | mirror removal |
| 23 | Phase 6 obsolete cross-feature callbacks removal | Phase 6 | callback backchannels | `DiscoveryPage` callback lattice / legacy facades | no new owner; explicit feature contracts remain | legacy callback compatibility surfaces | UI smoke + migration regression | feature interaction no longer callback-driven | deletion of callbacks and lingering facades |

## 4. Dependency graph

- `01 -> 02 -> 03`
- `03 -> 04`
- `03 -> 05`
- `04 + 05 -> 06`
- `04 + 05 + 06 -> 20`
- `06 -> 07`
- `06 -> 08`
- `07 + 08 -> 09`
- `09 -> 21`
- `21 -> 10`
- `21 -> 11`
- `10 + 11 -> 22`
- `22 -> 12`
- `06 + 12 -> 13`
- `12 + 09 -> 14`
- `12 + 14 -> 15`
- `15 -> 16`
- `09 + 06 -> 17`
- `13 + 14 + 15 + 16 + 17 -> 23`
- `all executable workpacks -> 18`
- `01 informs 19; 19 stays valid through all later workpacks`

## 5. Parallelism rules

Можно параллелить:
- `04` и `05` после завершения `03`
- `07` и `08` после завершения `06`
- `10` и `11` после завершения `21`
- `13` и `17` после завершения их общих зависимостей

Нельзя параллелить:
- `06` с `04/05`, потому что read model должен опираться на уже активированные owners
- `12` с `22`, потому что mirror removal без read cutover ломает UI
- `15` с `14`, потому что files owner должен читать уже вынесенный remote browse state
- `23` раньше завершения `13/14/15/16/17`, иначе удаление callback surfaces останется без replacement contracts

## 6. Deletion waves

- Wave A:
  - `02`, `03`
  - unlocks: conceptual ownership of `_localPeerIdKey`, page-side composition root
- Wave B:
  - `20`, `21`, `12`
  - unlocks: legacy discovery identity/trust fields, protocol dispatch facade, controller cache mirrors
- Wave C:
  - `13`, `14`, `16`, `17`, `23`
  - unlocks: `_clipboardHistory`, `_remoteShareOptions`, `_MediaPreviewCache`, obsolete cross-feature callbacks, lingering legacy facades
