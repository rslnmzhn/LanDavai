# Workpack: Phase 3 Discovery Read Model Cutover

## 1. Scope

- Переключить discovery UI read path с `DiscoveryController` на `Discovery read/application model`.
- Сохранить single-writer ownership в already-activated stores.
- Не входит: Phase 3 field deletion, Phase 4 protocol split, Phase 6 feature extraction.

## 2. Source linkage

- `Master phase`: Phase 3
- `Depends on`: `04`, `05`
- `Unblocks`: `07`, `20`, `23`
- `Related workpacks`: `03`, `14`

## 3. Problem slice

Master plan фиксирует, что widgets и sheets читают controller-owned maps напрямую. Этот slice выделен отдельно, потому что read cutover нельзя прятать внутрь store split workpacks.

## 4. Legacy owner and target owner

- `Legacy owner`: `DiscoveryController` direct read surface
- `Target owner`: `Discovery read/application model`
- `State seam closed`: UI projection separate from durable and session truths
- `Single write authority after cutover`: stores stay writers; read model writes only its own projection

## 5. Source of truth impact

- что сейчас является truth:
  - controller maps and mirrors are treated as both projection and truth
- что станет truth:
  - `DeviceRegistry`, `TrustedLanPeerStore`, later stores from other phases
- что станет projection:
  - `Discovery read/application model`
- что станет cache:
  - none beyond rebuildable projection state
- что станет temporary bridge only:
  - `LegacyDiscoveryFacade`

## 6. Read/write cutover

- `Legacy read path`: widgets and sheets read `DiscoveryController` directly
- `Target read path`: widgets and sheets read `Discovery read/application model`
- `Read switch point`: discovery UI no longer binds directly to controller-owned identity/trust collections
- `Legacy write path`: UI callbacks call broad controller methods
- `Target write path`: UI dispatches intents through read/application model into explicit owners
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

1. перечислить discovery UI read points that still bind to controller
2. собрать equivalent projection in `Discovery read/application model`
3. перевести widgets to projection reads
4. перевести UI intents to explicit owner dispatch path
5. оставить `LegacyDiscoveryFacade` only for temporary glue
6. прогнать UI smoke and migration regression tests
7. зафиксировать completion proof for legacy read surface retirement

## 9. Evidence and source anchors

- `Evidence level`: Confirmed from code
- `Source of truth`:
  - `docs/refactor_master_plan.md`
  - `lib/features/discovery/application/discovery_controller.dart` / `_devicesByIp`, `_trustedDeviceMacs`, `_ownerSharedCaches`, `_clipboardHistory`
  - `lib/features/discovery/presentation/discovery_page.dart` / feature-opening methods and direct controller consumption points
  - `lib/features/clipboard/presentation/clipboard_sheet.dart` / `final DiscoveryController controller`

## 10. Test gate

- До начала нужны: UI smoke tests, migration regression tests
- Подтверждают cutover: screen and sheet flows work without direct controller truth reads
- Hard stop failure:
  - any discovery-facing widget still requires controller-owned truth to function

## 11. Completion criteria

- discovery UI reads projection instead of broad controller maps
- durable writes are dispatched to explicit owners, not hidden in UI convenience methods
- `LegacyDiscoveryFacade` remains temporary only

## 12. Deletions unlocked

- unblocks `20` for controller field downgrade
- partially unblocks `23` for callback/facade removal

## 13. Anti-regression notes

- запрещено расширять `LegacyDiscoveryFacade`
- запрещено снова отдавать widgets доступ к controller-owned truth under a renamed API
