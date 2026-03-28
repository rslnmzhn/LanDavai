# 05 Files Part Graph Removal

Read first:
- `AGENTS.md`
- `refactor_context.md`
- `docs/refactor_master_plan.md`
- `docs/refactor_workpacks/00_index.md`

## Purpose

Remove the remaining `part / part of` cluster from files presentation so explorer and viewer code no longer live in one shared private namespace.

## Current Problem / Evidence

- `lib/features/files/presentation/file_explorer_page.dart` still declares:
  - `file_explorer_models.dart`
  - `file_explorer_recache_status.dart`
  - `local_file_viewer.dart`
  - `file_explorer_widgets.dart`
  - `file_explorer_tail_widgets.dart`
- ownership truth is no longer hidden there, but the remaining presentation seam is still coupled through one `part` graph
- `local_file_viewer.dart` is still large and implicitly tied to the main explorer library through shared private access

## Target State

- files presentation uses normal imports only
- explorer widgets, viewer surfaces, and status helpers live in standalone files with explicit dependencies
- no `part / part of` remains under the files presentation seam

## In Scope

- `lib/features/files/presentation/file_explorer_page.dart`
- `lib/features/files/presentation/file_explorer/*.dart`
- any new presentation files needed to replace the current part graph
- files/preview widget and smoke coverage touched by the split

## Out Of Scope

- redoing `FilesFeatureStateOwner`
- redoing `PreviewCacheOwner`
- shared-cache maintenance contract changes beyond the entry surface already stabilized by `04`
- broad files UX redesign

## Dependencies

- depends on `04`, because the files launch and maintenance contract should stop churning first

## Pull Request Cycle

### PR1

- inventory every private cross-file dependency in the current part graph
- define the standalone file boundaries and import graph

### PR2

- move explorer widgets, viewer surfaces, and helper types to normal library files
- switch `FileExplorerPage` and `LocalFileViewerPage` to explicit imports

### PR3

- delete the `part / part of` declarations
- add or refresh files/preview regression coverage
- run full proof

## Required Tests

- files feature owner tests
- preview cache owner tests
- widget or smoke coverage for explorer/viewer entry flows
- architecture guard checks for forbidden `part` backslides
- `flutter analyze`
- `flutter test`

## Completion Proof

- no `part / part of` remains in the files presentation seam
- files presentation compiles through explicit imports only
- explorer and viewer entry flows still pass with the same owner-backed contracts
