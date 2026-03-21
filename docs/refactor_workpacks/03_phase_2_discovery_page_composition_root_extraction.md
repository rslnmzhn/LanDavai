# Workpack: Phase 2 DiscoveryPage Composition Root Extraction

## 1. Scope

- Убрать dependency assembly из `DiscoveryPage`.
- Разорвать связь между widget lifecycle и dependency lifecycle.
- Не входит: Phase 3 ownership split внутри discovery state.

## 2. Source linkage

- `Master phase`: Phase 2
- `Depends on`: `01`, `02`
- `Unblocks`: `04`, `05`, `06`
- `Related workpacks`: `23`

## 3. Problem slice

Master plan зафиксировал, что `DiscoveryPage` выступает как UI-hosted composition root. Этот slice выделен отдельно, потому что пока страница создаёт graph сама, никакой честный owner cutover in discovery невозможен.

## 4. Legacy owner and target owner

- `Legacy owner`: `DiscoveryPage`
- `Target owner`: app-level composition root
- `State seam closed`: dependency lifecycle vs widget lifecycle
- `Single write authority after cutover`: app-level composition root for assembly; widgets own only ephemeral UI state
- `Forbidden writers`: `DiscoveryPage`, widget lifecycle methods, hidden service locators in the widget tree
- `Forbidden dual-write paths`: page-side dependency construction in parallel with extracted composition-root assembly

`app-level composition root`:
- `Derived planning helper, not a new architecture component`

## 5. Source of truth impact

- что сейчас является truth:
  - widget constructs repositories, services, and controller directly
- что станет truth:
  - injected dependency graph outside UI
- что станет projection:
  - `DiscoveryPage` becomes pure consumer of injected boundaries
- что станет cache:
  - none
- что станет temporary bridge only:
  - none

## 6. Read/write cutover

- `Legacy read path`: `DiscoveryPage` reads from objects it constructs itself
- `Target read path`: `DiscoveryPage` reads from injected boundaries
- `Read switch point`: page constructor or state no longer calls `AppDatabase.instance` or `DiscoveryController(...)`
- `Legacy write path`: widget lifecycle instantiates graph and owns teardown
- `Target write path`: composition root owns construction lifecycle
- `Write switch point`: first commit where graph assembly exits `DiscoveryPage`
- `Dual-read allowed?`: no
- `Dual-write allowed?`: no

## 7. Temporary bridge

- `No temporary bridge permitted for this workpack`

## 8. Concrete migration steps

1. inventory every assembly point inside `DiscoveryPage`
2. move graph construction above the UI boundary
3. pass only ready-made boundaries into the page
4. remove widget-owned instantiation of controller, repositories, and services
5. run `GATE-06`
6. record deletion proof for page-side assembly code

## 9. Evidence and source anchors

- `Evidence level`: Confirmed from code
- `Source of truth`:
  - `docs/refactor_master_plan.md`
  - `lib/features/discovery/presentation/discovery_page.dart` / `AppDatabase.instance`, `DiscoveryController(...)`, `_openFriendsSheet`, `_openClipboardSheet`, `_openFileExplorer`, `_openHistorySheet`
- `Compatibility anchors`:
  - no storage or wire anchor changes permitted in this workpack
- `Missing artifact`:
  - no code-visible extracted composition root exists yet in the current Dart-layer audit
- `Impact of uncertainty`:
  - the exact injection surface can vary, but page-side assembly must still disappear
- `Safest interim assumption`:
  - treat the extracted composition root as infrastructure above the widget tree only, never as a hidden locator inside the page

## 10. Test gate

- `До начала нужны`: `GATE-06`
- `Подтверждают cutover`: page entry and feature launch flows still work after page-side assembly is removed
- `Hard stop failure`: `DiscoveryPage` still constructs low-level dependencies after claimed cutover

## 11. Completion criteria

- `DiscoveryPage` no longer constructs repositories, services, or controller
- page remains able to open related feature flows through injected boundaries only

## 12. Deletions unlocked

- dependency assembly inside `DiscoveryPage`

## 13. Anti-regression notes

- запрещён скрытый service locator inside widget tree
- запрещено заменить page-side assembly новым singleton cluster
