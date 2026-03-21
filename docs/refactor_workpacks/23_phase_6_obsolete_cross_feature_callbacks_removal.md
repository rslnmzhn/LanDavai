# Workpack: Phase 6 Obsolete Cross-Feature Callbacks Removal

## 1. Scope

- Удалить callback backchannels и temporary facades после завершения feature extractions.
- Закрепить explicit feature contracts as the only interaction model.
- Не входит: новые owner splits; они already finished in preceding workpacks.

## 2. Source linkage

- `Master phase`: Phase 6
- `Depends on`: `13`, `14`, `15`, `16`, `17`
- `Unblocks`: `18`
- `Related workpacks`: `03`, `06`, `20`, `21`, `12`

## 3. Problem slice

Master plan требовал отдельный slice на удаление obsolete cross-feature callbacks. Без него даже после owner splits project остаётся связным через старые backchannels, а facades превращаются в permanent glue.

## 4. Legacy owner and target owner

- `Legacy owner`: callback lattice in discovery/files flows and lingering facades
- `Target owner`: no new owner; explicit feature owners and read models remain active
- `State seam closed`: feature interaction via explicit contracts instead of callback backchannels
- `Single write authority after cutover`: unchanged; each feature owner keeps its own seam

## 5. Source of truth impact

- что сейчас является truth:
  - feature coordination may still flow through callbacks and temporary facades
- что станет truth:
  - explicit owner/read-model boundaries only
- что станет projection:
  - view models remain owned by their feature/application boundaries
- что станет cache:
  - none
- что станет temporary bridge only:
  - legacy callback compatibility surfaces until this workpack completes

## 6. Read/write cutover

- `Legacy read path`: some feature interactions still read through `LegacyDiscoveryFacade` / `FileExplorerFacade` or callbacks
- `Target read path`: features read each other's outputs only through explicit contracts defined by completed workpacks
- `Read switch point`: no feature entry or sheet wiring depends on callback backchannels
- `Legacy write path`: user actions can still reach foreign feature state through callbacks/facades
- `Target write path`: actions reach only the owning feature boundary
- `Write switch point`: no cross-feature callback mutates foreign ownership seam
- `Dual-read allowed?`: no
- `Dual-write allowed?`: no

## 7. Temporary bridge

- `Bridge name`: legacy callback compatibility surfaces (`LegacyDiscoveryFacade` + `FileExplorerFacade`)
- `Why it exists`: temporary glue during Phase 3 and Phase 6 cutovers only
- `Phase introduced`: Phases 3 and 6
- `Max allowed lifetime`: through Phase 6 only
- `Deletion phase`: this workpack
- `Forbidden long-term use`: cannot survive as hidden integration layer

## 8. Concrete migration steps

1. inventory remaining cross-feature callbacks and facade-mediated interactions
2. prove each interaction has an explicit replacement boundary already active
3. remove callback backchannels one seam at a time
4. delete `LegacyDiscoveryFacade` and `FileExplorerFacade` if no remaining callers exist
5. run UI smoke and migration regression tests
6. record proof that feature interaction is no longer callback-driven

## 9. Evidence and source anchors

- `Evidence level`: Strong inference from code structure
- `Source of truth`:
  - `docs/refactor_master_plan.md`
  - `lib/features/discovery/presentation/discovery_page.dart` / feature-opening callbacks and flow wiring
  - `lib/features/clipboard/presentation/clipboard_sheet.dart` / controller dependency indicating old coupling style
  - `lib/features/files/presentation/file_explorer_page.dart` / part-based feature entry and legacy facade context from master plan

## 10. Test gate

- До начала нужны: UI smoke tests, migration regression tests
- Подтверждают cutover: feature flows still work without callback backchannels or legacy facades
- Hard stop failure:
  - any feature action still mutates foreign state through callback/facade after claimed cutover

## 11. Completion criteria

- obsolete cross-feature callbacks are removed
- `LegacyDiscoveryFacade` and `FileExplorerFacade` are deleted or proven unnecessary
- feature interaction uses explicit contracts only

## 12. Deletions unlocked

- obsolete cross-feature callbacks from discovery UI
- `LegacyDiscoveryFacade`
- `FileExplorerFacade`

## 13. Anti-regression notes

- запрещено оставить one callback “for convenience”; это reopens hidden ownership channel
- запрещено rename facades and keep them as permanent orchestration shell
