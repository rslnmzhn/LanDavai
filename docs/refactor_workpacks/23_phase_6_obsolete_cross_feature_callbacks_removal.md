# Workpack: Phase 6 Obsolete Cross-Feature Callbacks Removal

## 1. Scope

- Удалить callback backchannels and temporary facades after feature extractions are complete.
- Stage 1: remove `LegacyDiscoveryFacade` usages that survive after discovery, clipboard, remote-share, and history cutovers.
- Stage 2: remove files callback backchannels and `FileExplorerFacade`.
- Stage 3: prove no cross-feature callback mutates foreign ownership seams.
- Не входит: новые owner splits; они already finished in preceding workpacks.

## 2. Source linkage

- `Master phase`: Phase 6
- `Depends on`: `06`, `13`, `13a`, `13b`, `14`, `15`, `16`, `17`
- `Unblocks`: `18`
- `Related workpacks`: `03`, `20`, `21`

## 3. Problem slice

Master plan требовал отдельный slice на удаление obsolete cross-feature callbacks. Без него даже после owner splits project остаётся связным через старые backchannels, а facades превращаются в permanent glue. Этот workpack остаётся одним файлом только потому, что внутренняя staging-логика above жёстко фиксирует execution order.

## 4. Legacy owner and target owner

- `Legacy owner`: callback lattice in discovery, clipboard, files, and history flows plus lingering facades
- `Target owner`: no new owner; explicit feature owners and read models remain active
- `State seam closed`: feature interaction through explicit contracts instead of callback backchannels
- `Single write authority after cutover`: unchanged; each explicit feature owner keeps its own seam
- `Forbidden writers`: widgets or pages mutating foreign feature state through callbacks, `LegacyDiscoveryFacade`, `FileExplorerFacade`, any convenience closure that bypasses owning boundaries
- `Forbidden dual-write paths`: explicit owner writes in parallel with callback backchannel writes to the same foreign seam

## 5. Source of truth impact

- что сейчас является truth:
  - feature coordination may still flow through callbacks and temporary facades
- что станет truth:
  - explicit owner and read-model boundaries only
- что станет projection:
  - feature-specific view models remain owned by their explicit boundaries
- что станет cache:
  - none
- что станет temporary bridge only:
  - legacy callback compatibility surfaces until this workpack completes

## 6. Read/write cutover

- `Legacy read path`: some feature interactions still read through `LegacyDiscoveryFacade`, `FileExplorerFacade`, or callback-fed state
- `Target read path`: features read each other's outputs only through explicit contracts defined by completed workpacks
- `Read switch point`: no feature entry, sheet wiring, or screen-level bridge depends on callback backchannels
- `Legacy write path`: user actions can still reach foreign feature state through callbacks or facades
- `Target write path`: actions reach only the owning feature boundary
- `Write switch point`: no cross-feature callback mutates foreign ownership seams
- `Dual-read allowed?`: no
- `Dual-write allowed?`: no

## 7. Temporary bridge

- `Bridge name`: `LegacyDiscoveryFacade`, `FileExplorerFacade`, remaining callback compatibility surfaces
- `Why it exists`: temporary glue during Phase 3 and Phase 6 cutovers only
- `Phase introduced`: Phases 3 and 6
- `Max allowed lifetime`: through Phase 6 only
- `Deletion phase`: this workpack
- `Forbidden long-term use`: cannot survive as hidden integration layer

## 8. Concrete migration steps

1. inventory remaining cross-feature callbacks and facade-mediated interactions
2. remove `LegacyDiscoveryFacade` usages after `06`, `13`, `13a`, `13b`, and `14` are complete
3. remove files callback backchannels and `FileExplorerFacade` after `15` and `16`
4. delete any remaining callback path that mutates foreign ownership seams after `17`
5. run `GATE-06` and `GATE-07`
6. record proof that feature interaction is no longer callback-driven

## 9. Evidence and source anchors

- `Evidence level`: Strong inference from code structure
- `Source of truth`:
  - `docs/refactor_master_plan.md`
  - `lib/features/discovery/presentation/discovery_page.dart` / feature-opening callbacks and flow wiring
  - `lib/features/clipboard/presentation/clipboard_sheet.dart` / controller dependency indicating old coupling style
  - `lib/features/files/presentation/file_explorer_page.dart` / files feature entry boundary and `part` graph
- `Compatibility anchors`:
  - none new; this workpack must preserve all already-frozen anchors from previous slices and must not reopen them
- `Missing artifact`:
  - the exact final callback inventory depends on how temporary facades and bridges are implemented during preceding workpacks
- `Impact of uncertainty`:
  - callback deletion order can vary slightly, but the dependency chain in section 2 cannot
- `Safest interim assumption`:
  - if any callback still mutates foreign ownership seam after dependencies are green, this workpack is not complete

## 10. Test gate

- `До начала нужны`: `GATE-06`, `GATE-07`
- `Подтверждают cutover`: feature flows still work without callback backchannels or legacy facades
- `Hard stop failure`: any feature action still mutates foreign state through callback or facade after claimed cutover

## 11. Completion criteria

- obsolete cross-feature callbacks are removed
- `LegacyDiscoveryFacade` and `FileExplorerFacade` are deleted
- feature interaction uses explicit contracts only

## 12. Deletions unlocked

- obsolete cross-feature callbacks from discovery UI
- `LegacyDiscoveryFacade`
- `FileExplorerFacade`
- final `ClipboardSheet -> DiscoveryController` dependency surface if any wrapper still survived until this workpack

## 13. Anti-regression notes

- запрещено оставить one callback for convenience; this reopens hidden ownership channel
- запрещено rename facades and keep them as permanent orchestration shell
