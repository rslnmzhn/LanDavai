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

## PR1 Inventory Result

### Prerequisite check

- Dependency `04_shared_cache_maintenance_contract_cutover.md` is satisfied.
- PR1 is inventory-only. No `part` removal or hybrid import rewiring happens here.
- Current owner baseline remains external to files presentation:
  - `FilesFeatureStateOwner`
  - `PreviewCacheOwner`
  - `SharedCacheMaintenanceBoundary`
  - `SharedCacheCatalog`
  - `SharedCacheIndexStore`
- This seam is now about hidden presentation coupling only, not about ownership truth extraction.

### Production part-graph inventory

| File | Symbols / cluster | Kind | Owner / boundary dependencies consumed | Current classification |
| --- | --- | --- | --- | --- |
| `lib/features/files/presentation/file_explorer_page.dart` | `FileExplorerPage`, `_FileExplorerPageState`, `_FileExplorerLaunchConfig`, launch-root helpers, refresh/remove/open handlers | page + launch adapter | `FilesFeatureStateOwner`, `PreviewCacheOwner`, `SharedCacheMaintenanceBoundary`, `SharedCacheCatalog`, `SharedCacheIndexStore` | mixed page shell plus hidden shared-private coupling root |
| `lib/features/files/presentation/file_explorer/file_explorer_models.dart` | `_supportedImageExtensions`, `_supportedVideoExtensions`, `_supportedAudioExtensions`, `_supportedTextExtensions`, `_useMediaKitForPlayback`, `_ExplorerMenuAction` | model/type + helper constants | platform check only | hidden shared-private coupling residue |
| `lib/features/files/presentation/file_explorer/file_explorer_recache_status.dart` | `_SharedRecacheStatusCard` | recache/progress surface | `SharedCacheMaintenanceProgress`, theme tokens | presentation-only owner-backed read consumer |
| `lib/features/files/presentation/file_explorer/local_file_viewer.dart` | `LocalFileViewerPage`, media/audio/image/pdf/text viewer widgets, playback helpers | modal/viewer | `PreviewCacheOwner` plus media libraries | viewer surface trapped inside shared library scope |
| `lib/features/files/presentation/file_explorer/file_explorer_widgets.dart` | `_ExplorerPathHeader`, `_ExplorerEntityTile`, `_ExplorerEntityLeading`, `_ExplorerFilePreview`, `_ExplorerVideoPreview`, `_ExplorerAudioPreview` | widget section | `PreviewCacheOwner`, `FilesFeatureEntry` | presentation-only widgets with hidden shared-private coupling |
| `lib/features/files/presentation/file_explorer/file_explorer_tail_widgets.dart` | `_ExplorerEntityGridTile`, `_GridNameLabel`, `_DisplayModeToggle`, `_ExplorerErrorBanner`, `_LocalFileKind` | widget section + helper type | `PreviewCacheOwner`, `FilesFeatureEntry` | presentation-only widgets plus shared-private helper type residue |

Effective production seam around the part graph:

- `DiscoveryPage` opens `FileExplorerPage.launch(...)`.
- `DiscoveryReceivePanelSheet` imports `file_explorer_page.dart` only to access `LocalFileViewerPage`.
- `FileExplorerPage` itself depends on part-only widgets, menu types, recache card, and viewer page from the same private library namespace.

### Private cross-file dependency inventory

Concrete part-only dependencies currently shared across files:

- `file_explorer_page.dart` -> `file_explorer_models.dart`
  - source symbols:
    - `_ExplorerMenuAction`
    - `_supported*Extensions` only indirectly via child widgets/viewer
  - why it depends on `part`:
    - `_ExplorerMenuAction` is private but used by page popup menu and sort mapping
  - PR2 direction:
    - `_ExplorerMenuAction` should become a narrow standalone type or be deleted by moving menu handling into a standalone imported widget

- `file_explorer_page.dart` -> `file_explorer_recache_status.dart`
  - source symbol:
    - `_SharedRecacheStatusCard`
  - why it depends on `part`:
    - private status widget rendered from the page body
  - PR2 direction:
    - standalone imported recache/progress widget file

- `file_explorer_page.dart` -> `file_explorer_widgets.dart`
  - source symbols:
    - `_ExplorerPathHeader`
    - `_ExplorerEntityTile`
    - `_DisplayModeToggle` indirectly through tail widgets split
  - why it depends on `part`:
    - page uses these widgets directly while they stay private to the shared library
  - PR2 direction:
    - standalone imported explorer widget file(s)

- `file_explorer_page.dart` -> `file_explorer_tail_widgets.dart`
  - source symbols:
    - `_ExplorerEntityGridTile`
    - `_ExplorerErrorBanner`
    - `_DisplayModeToggle`
  - why it depends on `part`:
    - page renders these private widgets directly
  - PR2 direction:
    - standalone imported widget file(s)

- `file_explorer_page.dart` -> `local_file_viewer.dart`
  - source symbol:
    - `LocalFileViewerPage`
  - why it depends on `part`:
    - viewer page is declared in the same library instead of as its own importable surface
  - PR2 direction:
    - standalone explicit viewer page import

- `file_explorer_widgets.dart` -> `file_explorer_models.dart`
  - source symbols:
    - `_supportedImageExtensions`
    - `_supportedVideoExtensions`
    - `_supportedAudioExtensions`
  - why it depends on `part`:
    - preview leading widgets classify files through private shared constants
  - PR2 direction:
    - move to a narrow shared public-but-local helper/type file, or split preview classifier helpers per widget cluster

- `file_explorer_tail_widgets.dart` -> `file_explorer_widgets.dart`
  - source symbol:
    - `_ExplorerEntityLeading`
  - why it depends on `part`:
    - grid tile directly reuses explorer-leading private widget
  - PR2 direction:
    - explicit imported widget dependency or a narrower shared leading/preview widget file

- `local_file_viewer.dart` -> `file_explorer_models.dart`
  - source symbols:
    - `_supportedImageExtensions`
    - `_supportedVideoExtensions`
    - `_supportedAudioExtensions`
    - `_supportedTextExtensions`
    - `_useMediaKitForPlayback`
  - why it depends on `part`:
    - viewer file-kind detection and player selection rely on shared private constants/getters
  - PR2 direction:
    - explicit imported viewer-support/types file

- `local_file_viewer.dart` -> `file_explorer_tail_widgets.dart`
  - source symbol:
    - `_LocalFileKind`
  - why it depends on `part`:
    - file-kind enum is private and declared in a different part file than the viewer
  - PR2 direction:
    - move to a standalone narrow type file next to viewer support

- `DiscoveryReceivePanelSheet` -> `file_explorer_page.dart`
  - source symbol:
    - `LocalFileViewerPage`
  - why it depends on current structure:
    - viewer surface is not importable independently, so an unrelated discovery surface imports the whole explorer page library
  - PR2 direction:
    - switch discovery to import the standalone viewer file directly

Private cross-file dependencies that do not need to survive PR2 as shared symbols:

- `_mediaUriFromFilePath(...)`
- `_formatPlaybackDuration(...)`
- `_resolveVideoAspectRatio(...)`
- `_ViewerError`

These are viewer-local helpers and should stay viewer-local after the split, not become shared pseudo-API.

### Owner-backed dependencies vs presentation residue

External owner-backed dependencies that must remain external:

- `FilesFeatureStateOwner`
  - canonical owner for explorer roots/navigation/filter/sort/view state
- `PreviewCacheOwner`
  - canonical owner for preview thumbnails, video previews, audio covers, and preview cleanup policy
- `SharedCacheMaintenanceBoundary`
  - canonical entry/progress boundary for shared-cache recache/remove
- `SharedCacheCatalog`
  - metadata truth only, used by launch-root loading
- `SharedCacheIndexStore`
  - index truth only, used by launch-root loading

Ephemeral UI state inside the current seam:

- `FileExplorerPage`
  - `_searchController`
  - `_launchErrorMessage`
  - `_ownedOwner` / `_attachedOwner` as page lifecycle attachment state, not feature truth
- `LocalFileViewerPage` and nested viewer widgets
  - playback position, duration, play/pause, preview/loading flags, text preview truncation state
- preview tile widgets
  - in-memory thumbnail/cover `Future` state

Hidden presentation residue caused by `part`:

- shared file-kind constants used by both explorer preview widgets and the standalone viewer
- private enum/type usage across files instead of explicit imports
- viewer exposure bundled into the explorer page library

No current evidence suggests moving any owner truth into files presentation for PR2.

### Proposed standalone file boundaries for PR2

Explicit split map that avoids recreating the same hidden coupling:

- `file_explorer_page.dart`
  - thin page/screen entry only
  - owner attach/init/dispose
  - launch-root loading helpers unless they are extracted into a narrow launch helper

- standalone explorer widget file(s)
  - path header
  - list tile
  - grid tile
  - leading/preview widgets
  - display-mode toggle
  - error banner

- standalone viewer surface file
  - `LocalFileViewerPage`
  - viewer-local helper widgets
  - viewer-only playback helpers

- standalone viewer/explorer support types file
  - file-kind enum
  - supported extension sets
  - media-kit platform switch
  - only if kept narrow and importable; not a generic helper bag

- standalone recache/progress surface file
  - `_SharedRecacheStatusCard` replacement with explicit imports

Avoid in PR2:

- one giant replacement helper library
- keeping `LocalFileViewerPage` coupled to `file_explorer_page.dart`
- duplicating file-kind models in both explorer and viewer during transition

### Production structure vs test/support coupling

Tests inspected:

- `test/files_feature_state_owner_test.dart`
  - protects owner truth, not `part` structure
- `test/preview_cache_owner_test.dart`
  - protects preview owner truth, not files presentation modularity
- `test/smoke_test.dart`
  - no direct `FileExplorerPage` or `LocalFileViewerPage` coverage

Additional findings:

- no dedicated widget/smoke tests were found for explorer entry
- no dedicated widget/smoke tests were found for viewer entry
- no existing architecture guard test was found that fails on forbidden files-presentation `part` usage

This means:

- `GATE-02` proof is good for owner-backed maintenance seams
- `GATE-03` proof is weak for explorer/viewer entry survivability specifically
- `GATE-07` proof is currently absent for this seam and will need later hardening

### PR2 seam contract

- `Legacy owner / legacy route`
  - current hidden-coupling route is the `file_explorer_page.dart` library plus five `part` files sharing one private namespace
  - concrete route:
    - explorer page -> private widgets/status/types/viewer declared in other files ->
      shared constants/enums/helpers only visible because of `part / part of`

- `Target owner / target boundary`
  - files presentation composed from normal Dart files with explicit imports only
  - constraints:
    - `FileExplorerPage` becomes a narrower entry surface
    - `LocalFileViewerPage` becomes a standalone importable viewer surface
    - models/progress helpers use narrow explicit types
    - no hidden shared-private namespace remains
    - extracted owners and boundaries stay external and authoritative

- `Read switch point`
  - first production import/read switch:
    - `DiscoveryReceivePanelSheet` must stop importing `file_explorer_page.dart` just to reach `LocalFileViewerPage`
    - viewer entry should move to an explicit viewer import surface

- `Write switch point`
  - first symbol cluster to leave `part`:
    - `file_explorer_models.dart`
    - `local_file_viewer.dart`
  - these two currently create the strongest shared-private coupling because viewer logic depends on private enum/constants from another part file

- `Forbidden writers`
  - `FileExplorerPage`
  - `LocalFileViewerPage`
  - extracted widgets/helpers holding feature truth
  - helper facades or pseudo-libraries acting as hidden owners
  - `part`-based replacements that preserve the same hidden coupling

- `Forbidden dual-write / dual-route paths`
  - old `part` declarations plus new explicit-import route for the same symbol cluster
  - old shared private namespace plus duplicated public replacement type acting as truth for the same UI concern
  - explorer and viewer both carrying duplicated file-kind models/constants during transition

- `Expected consumers of the future split`
  - `FileExplorerPage`
  - `LocalFileViewerPage`
  - extracted explorer widgets
  - extracted recache/progress widgets
  - `DiscoveryReceivePanelSheet` as an external viewer consumer
  - smoke/widget tests for explorer/viewer survivability

- `Files PR2 will need to change`
  - must change:
    - `lib/features/files/presentation/file_explorer_page.dart`
    - `lib/features/files/presentation/file_explorer/file_explorer_models.dart`
    - `lib/features/files/presentation/file_explorer/file_explorer_recache_status.dart`
    - `lib/features/files/presentation/file_explorer/local_file_viewer.dart`
    - `lib/features/files/presentation/file_explorer/file_explorer_widgets.dart`
    - `lib/features/files/presentation/file_explorer/file_explorer_tail_widgets.dart`
  - likely change:
    - `lib/features/discovery/presentation/discovery_receive_panel_sheet.dart`
    - `test/smoke_test.dart`
    - any new explorer/viewer smoke/widget regression tests

### PR1 conclusion

- PR2 is unblocked.
- The target files presentation split is explicit enough for a non-speculative extraction.
- No blocker from `07_shared_folder_cache_repository_split.md` was found; that infra split is downstream and separate.
- `10_architecture_guard_and_regression_hardening.md` is not a blocker, but current guard proof for forbidden `part` regressions is still weak.
- The seam definition avoids recreating the same hidden coupling under different file names.
- Extracted owners and boundaries remain external and authoritative.

## Completion Proof

- no `part / part of` remains in the files presentation seam
- files presentation compiles through explicit imports only
- explorer and viewer entry flows still pass with the same owner-backed contracts
