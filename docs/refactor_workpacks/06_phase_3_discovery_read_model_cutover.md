# Workpack: Phase 3 Discovery Read/Application Model Cutover

## 1. Scope

- Переключить discovery UI read path с `DiscoveryController` на `Discovery read/application model`.
- Сохранить single-writer ownership в `DeviceRegistry`, `TrustedLanPeerStore`, `InternetPeerEndpointStore` и later phase owners.
- Не входит: controller field deletion, protocol split, Phase 6 feature extraction.

## 2. Source linkage

- `Master phase`: Phase 3
- `Depends on`: `03a`, `04`, `05`
- `Unblocks`: `07`, `20`, `14`, `23`
- `Related workpacks`: `03`, `13`, `13a`

## 3. Problem slice

Master plan фиксирует, что widgets и sheets читают broad controller-owned truth directly. Этот slice выделен отдельно, потому что read cutover нельзя прятать внутрь store split workpacks: он задаёт единственный discovery-facing projection boundary.

## 4. Legacy owner and target owner

- `Legacy owner`: `DiscoveryController` direct read surface
- `Target owner`: `Discovery read/application model`
- `State seam closed`: discovery UI projection separate from durable and session truths
- `Single write authority after cutover`: target stores remain writers; read model writes only its own projection
- `Forbidden writers`: `DiscoveryPage`, widgets, repositories, `LegacyDiscoveryFacade` beyond temporary glue
- `Forbidden dual-write paths`: controller-owned truth mutation in parallel with explicit owner writes; projection state used as hidden domain writer

## 5. Source of truth impact

- что сейчас является truth:
  - controller maps and mirrors are treated as both projection and truth
- что станет truth:
  - `DeviceRegistry`, `TrustedLanPeerStore`, `InternetPeerEndpointStore`, later phase stores for their seams
- что станет projection:
  - `Discovery read/application model`
- что станет cache:
  - none beyond rebuildable projection state
- что станет temporary bridge only:
  - `LegacyDiscoveryFacade`

## 6. Read/write cutover

- `Legacy read path`: widgets and sheets read `DiscoveryController` directly
- `Target read path`: widgets and sheets read `Discovery read/application model`
- `Read switch point`: discovery UI no longer binds directly to controller-owned identity, trust, or peer collections
- `Legacy write path`: UI callbacks call broad controller methods
- `Target write path`: UI dispatches intents through read/application model into explicit owners only
- `Write switch point`: durable writes stop being reachable through generic controller convenience surface
- `Dual-read allowed?`: yes, for temporary UI parity comparison only
- `Dual-write allowed?`: no

## 7. Temporary bridge

- `Bridge name`: `LegacyDiscoveryFacade`
- `Why it exists`: preserve screen-level integration while direct controller reads are being retired
- `Phase introduced`: Phase 3
- `Max allowed lifetime`: through Phase 6 only
- `Deletion phase`: `23_phase_6_obsolete_cross_feature_callbacks_removal.md`
- `Forbidden long-term use`: cannot become a renamed mega-controller

## 8. Concrete migration steps

1. inventory discovery UI read points that still bind to controller-owned truth
2. map device, trust, and internet peer reads to explicit owners
3. build equivalent projection in `Discovery read/application model`
4. switch widgets and sheets to projection reads
5. reroute UI intents to explicit owners only
6. keep `LegacyDiscoveryFacade` as temporary glue only
7. run `GATE-06` and `GATE-07`
8. capture proof that direct controller truth reads can be removed

## 9. Evidence and source anchors

- `Evidence level`: Confirmed from code
- `Source of truth`:
  - `docs/refactor_master_plan.md`
  - `lib/features/discovery/application/discovery_controller.dart` / `_devicesByIp`, `_trustedDeviceMacs`, `_friends`, `_ownerSharedCaches`, `_clipboardHistory`
  - `lib/features/discovery/presentation/discovery_page.dart` / feature-opening methods and direct controller consumption points
  - `lib/features/clipboard/presentation/clipboard_sheet.dart` / `ClipboardSheet`, `final DiscoveryController controller`
- `Compatibility anchors`:
  - `known_devices`
  - `friends`
  - `app_settings`

## 10. Test gate

- `До начала нужны`: `GATE-06`, `GATE-07`
- `Подтверждают cutover`: discovery page and dependent sheets work without direct controller truth reads
- `Hard stop failure`: any discovery-facing widget still requires controller-owned truth to function

## 11. Completion criteria

- discovery UI reads projection instead of broad controller maps
- durable writes are dispatched to explicit owners, not hidden in UI convenience methods
- `LegacyDiscoveryFacade` remains temporary only

## 12. Deletions unlocked

- unblocks `20` for controller field and method downgrade
- partially unblocks `23` for callback and facade removal

## 13. Anti-regression notes

- запрещено расширять `LegacyDiscoveryFacade`
- запрещено снова отдавать widgets доступ к controller-owned truth under a renamed API
