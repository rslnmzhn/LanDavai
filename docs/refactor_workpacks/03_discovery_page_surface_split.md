# Workpack 03: Discovery Page Surface Split

## Purpose

Разрезать `DiscoveryPage` как god-page на отдельные presentation surfaces.
Это UI decomposition workpack, not a new owner split.

## Current evidence

- `lib/features/discovery/presentation/discovery_page.dart` is the largest Dart file in `lib/`
- one page still bundles:
  - main discovery content
  - add-share and device-action menus
  - history sheet
  - clipboard sheet entry
  - receive panel entry
  - video-link flow entry
  - action bar and progress widgets

## Target state

- `DiscoveryPage` becomes a thin screen shell
- major UI surfaces move into dedicated presentation files
- page-level feature launch code shrinks materially
- extracted owners remain external and authoritative

## In scope

- `lib/features/discovery/presentation/discovery_page.dart`
- new supporting presentation files under `lib/features/discovery/presentation/`
- related discovery smoke/widget tests

## Out of scope

- shared-cache bridge removal
- local peer identity extraction
- transfer/video-link domain redesign
- protocol or repository refactors

## Pull Request Cycle

1. Inventory the major UI surfaces and launcher methods inside `DiscoveryPage`.
2. Extract focused widgets/sheets/launcher helpers with explicit inputs.
3. Leave page-local ephemeral UI state only where it is truly screen-local.
4. Remove obsolete inline modal/entry lattice from the main page file.
5. Run `flutter analyze`, discovery entry smokes, and full `flutter test`.

## Required test gates

- `GATE-03`
- `GATE-08`

## PR1 Inventory Result

### Prerequisite check

- Dependencies are satisfied in the current baseline:
  - `02_discovery_boundary_factory_extraction.md`
  - `04_shared_cache_maintenance_contract_cutover.md`
  - `08_transfer_video_link_separation.md`
- PR1 is inventory-only. No widget extraction happens here.
- Current owner baseline remains external to `DiscoveryPage`:
  - `DiscoveryReadModel`
  - `RemoteShareBrowser`
  - `TransferSessionCoordinator`
  - `VideoLinkSessionBoundary`
  - `SharedCacheMaintenanceBoundary`
  - `PreviewCacheOwner`
  - `RemoteClipboardProjectionStore`
  - `ClipboardHistoryStore`

### Production page-surface inventory

| Surface | Kind | Current dependency inputs | Classification |
| --- | --- | --- | --- |
| `DiscoveryPage.build()` scaffold/layout | screen shell | `DiscoveryController`, `DiscoveryReadModel`, `SharedCacheMaintenanceBoundary`, `VideoLinkSessionBoundary`, `TransferSessionCoordinator`, page-local video selection/loading state | monolithic screen shell |
| `mainContent` block in `build()` | screen section | `DiscoveryReadModel.devices`, `DiscoveryController.errorMessage`, `DiscoveryController.isManualRefreshInProgress`, `TransferSessionCoordinator` upload/download status | owner-backed read consumer plus inline layout residue |
| `_NetworkSummaryCard` | card/section | `DiscoveryReadModel` | presentation-only owner-backed read consumer |
| `_ErrorBanner` | status surface | `DiscoveryController.errorMessage` | presentation-only shell read consumer |
| `_TransferProgressCard` | status/progress surface | `TransferSessionCoordinator` | presentation-only owner-backed read consumer |
| `_DeviceTile` + `_StatusChip` | list item surface | `DiscoveredDevice`, page callbacks for select/open actions menu | presentation-only plus page launcher dependency |
| `_EmptyState` | empty-state section | refresh callback only | presentation-only |
| `_SideMenuDrawer` | menu shell | forwards explicit props into `_SideMenuActions` | presentation-only wrapper |
| `_SideMenuActions` | side menu section | open friends/settings/clipboard/history/files actions, refresh action, `VideoLinkSessionBoundary`, local shareable video list/selection state, copy-link/toggle callbacks | presentation surface with launcher inputs |
| `_VideoLinkServerCard` | card/section | `VideoLinkSessionBoundary`, local shareable video list/selection/loading state, copy/toggle callbacks | presentation-only owner-backed read consumer plus screen-local selection inputs |
| `_ActionBar` | bottom action section | `DiscoveryController` add/indexing status, `SharedCacheMaintenanceBoundary` recache progress, `TransferSessionCoordinator` send status, receive/add/send callbacks | mixed presentation surface with explicit launcher inputs and shell reads |
| `_SharedRecacheActionButton` | status/progress surface | recache/indexing progress and ETA values | presentation-only |
| `ClipboardSheet` launch | modal sheet entry | `DiscoveryController`, `DiscoveryReadModel`, `ClipboardHistoryStore`, `RemoteClipboardProjectionStore` | existing extracted surface entered from page |
| `AppSettingsSheet` launch | modal sheet entry | `DiscoveryReadModel.settings`, settings command callbacks, `DesktopWindowService` side effect | existing extracted surface entered from page |
| friends bottom sheet from `_openFriendsSheet()` | modal sheet | `DiscoveryController`, `DiscoveryReadModel`, controller friend commands | inline modal residue |
| history bottom sheet from `_openHistorySheet()` | modal sheet | `DownloadHistoryBoundary`, `DiscoveryController.openHistoryPath(...)` | inline modal residue |
| add-share bottom sheet from `_openAddShareMenu()` | modal sheet | `DiscoveryController.addSharedFolder()`, `addSharedFiles()`, `_reloadShareableVideoFiles()` | inline modal residue |
| device actions menu from `_openDeviceActionsMenu()` | menu/action launcher | `DiscoveryController.hasPendingFriendRequestForDevice()`, `sendFriendRequest()`, rename dialog path | inline launcher residue |
| rename dialog from `_showRenameDialog()` | dialog | `DiscoveryController.renameDeviceAlias(...)` | inline dialog residue |
| `_ReceivePanelSheet` | stateful modal sheet | `RemoteShareBrowser`, `PreviewCacheOwner`, `TransferSessionCoordinator`, refresh callback | already isolated widget class but still lives in the giant file |
| `_RemoteFilePreview` | preview tile | `RemoteBrowseFileChoice.previewPath` | presentation-only owner-backed read consumer |
| `FileExplorerPage.launch(...)` navigation entry from `_openFileExplorer()` | full-screen feature entry | `SharedCacheMaintenanceBoundary`, `SharedCacheCatalog`, `SharedCacheIndexStore`, `PreviewCacheOwner`, owner MAC, receive dirs | legitimate feature entry, but launcher still lives inline in page |

### Launcher/routing inventory

Launchers that are mostly presentation entry helpers:

- `_openClipboardSheet()`
  - initiator: side menu
  - downstream: `ClipboardSheet`
  - should move with menu/sheet entry helper or remain as a thin shell helper
  - not a hidden feature coordinator today
- `_openSettingsSheet()`
  - initiator: side menu
  - downstream: `AppSettingsSheet`
  - mostly a presentation launcher plus settings command mapping
- `_openHistorySheet()`
  - initiator: side menu
  - downstream: inline history sheet
  - should move with extracted history surface
- `_openFriendsSheet()`
  - initiator: side menu
  - downstream: inline friends sheet
  - should move with extracted friends surface
- `_openReceivePanel()`
  - initiator: action bar receive button
  - downstream: `_ReceivePanelSheet`
  - should move with extracted receive entry surface
- `_openFileExplorer()`
  - initiator: side menu files action
  - downstream: `FileExplorerPage.launch(...)`
  - legitimate feature entry launcher, but should not stay hidden inside a giant page file

Launchers/helpers that still mix routing/adaptation and therefore need explicit extraction boundaries in PR2:

- `_reloadShareableVideoFiles()`
  - initiator: page init/update, side menu open, add-share completion, file explorer return
  - downstream: `_listShareableVideoFiles()`
  - role: owner-backed read adaptation into page-local video-entry state
  - risk: if left in the page after extraction, it becomes a local presentation coordinator hub
- `_publishSelectedVideoLink()`
  - initiator: video-link card / toggle flow
  - downstream: `VideoLinkSessionBoundary.publishVideoLinkShare(...)`
  - role: command launcher with password/selection validation
  - should move with the extracted video-link entry surface
- `_toggleVideoLinkServer(...)`
  - initiator: video-link card toggle
  - downstream: `_reloadShareableVideoFiles()`, `_publishSelectedVideoLink()`, `_confirmStopVideoLinkShare()`, `VideoLinkSessionBoundary.stopVideoLinkShare()`
  - role: cross-step UX flow
  - should move with the extracted video-link surface
- `_openAddShareMenu()`
  - initiator: bottom action bar add button
  - downstream: controller add-share commands plus local video-list refresh
  - role: feature entry launcher plus post-action UI refresh
  - should move with an extracted add-share entry surface
- `_openDeviceActionsMenu(...)`
  - initiator: device tile long-press/right-click
  - downstream: rename dialog and friend request command paths
  - role: device action router
  - should move with the extracted device-list/device-actions surface

Legitimate page-local shell helpers that may remain thin after PR2 if they do not grow:

- `_handleInfoMessages()` snackbar bridge for controller info notices
- `_copyToClipboard(...)`
- formatting helpers (`_formatBytes`, `_formatTime`, `_isVideoPath`, `_resolveCacheFilePath`)

### Screen-local state vs feature truth

Truly ephemeral screen-local UI state:

- `_shareableVideoFiles`
  - local presentation projection for the video-link entry menu
  - derived from `SharedCacheCatalog` + `SharedCacheIndexStore`
  - not canonical shared-cache truth
- `_selectedShareableVideoId`
  - local video picker selection
  - safe to keep local to the eventual video-link entry surface
- `_isLoadingShareableVideoFiles`
  - local async spinner state for reloading video choices
  - safe to keep local to the eventual video-link entry surface
- `_ReceivePanelSheetState._previewingFileId`
  - local preview-loading spinner state
  - safe to remain inside the receive panel surface

Owner-backed feature state that must remain external:

- device discovery/read state -> `DiscoveryReadModel`
- controller shell notices, selected device, add-share/indexing status -> `DiscoveryController`
- remote browse projection and selection state -> `RemoteShareBrowser`
- transfer progress/incoming requests -> `TransferSessionCoordinator`
- video-link active session and watch URL -> `VideoLinkSessionBoundary`
- shared-cache recache progress -> `SharedCacheMaintenanceBoundary`
- local/remote clipboard truth -> `ClipboardHistoryStore`, `RemoteClipboardProjectionStore`
- download history truth -> `DownloadHistoryBoundary`

Dangerous residue if left page-local after the split:

- the video-link file-list reload/publish/toggle flow as one implicit page coordinator
- the device-actions flow (rename + friend actions) if extracted widgets start holding temporary copies of device/friend truth
- the add-share launcher plus post-refresh behavior if it gets hidden in a generic launcher helper instead of a focused surface

### Extraction map for PR2

Focused extraction candidates:

- discovery screen shell
  - keep `DiscoveryPage` as thin scaffold/layout host only
  - keep AnimatedBuilder wiring narrow and explicit
- device-list section
  - includes network summary, error/transfer banners, empty state, device list, device tile action entry
- side-menu surface
  - includes `_SideMenuDrawer`, `_SideMenuActions`, and the video-link card entry area
- friends sheet surface
  - move the entire inline `_openFriendsSheet()` body into a dedicated modal widget/file
- settings sheet launcher helper
  - keep `AppSettingsSheet` external, move the callback mapping out of the giant page body
- history sheet surface
  - move the inline `_openHistorySheet()` body into a dedicated modal widget/file
- add-share entry surface
  - move `_openAddShareMenu()` into a focused launcher/sheet with explicit inputs only
- receive panel surface
  - `_ReceivePanelSheet`, owner/folder pickers, and remote preview request flow should move out of the giant file together
- bottom action/status surface
  - `_ActionBar`, `_AdaptiveActionButton`, `_SharedRecacheActionButton`

Non-goals for PR2:

- do not centralize all launchers into one new menu/helper hub
- do not create a new presentation bag that mirrors the whole page API
- do not move owner-backed truth into extracted widgets

### Production presentation structure vs test/support coupling

Production structure:

- `DiscoveryPage` is the real presentation hub for:
  - scaffold/layout
  - side menu
  - bottom action bar
  - friends/history/add-share/receive launchers
  - device action routing
  - local video-link picker state

Test/support coupling inspected:

- `test/smoke_test.dart`
  - verifies basic `DiscoveryPage` render
  - verifies `DiscoveryPageEntry` boot
  - verifies the receive flow opens `_ReceivePanelSheet`
- no dedicated widget tests were found for:
  - friends sheet
  - settings launcher
  - history sheet
  - add-share menu
  - device actions menu
  - video-link side-menu card

This means PR2 will need careful targeted UI regression proof around extracted launch flows; current proof is strongest for entry boot and receive panel survivability.

### PR2 seam contract

Legacy owner / legacy route:

- the current monolithic route is `DiscoveryPage.build()` plus inline launcher methods and embedded private widgets in the same file
- one file still hosts:
  - scaffold/layout shell
  - side menu and video-link card
  - device list and device actions
  - friends/history/add-share/receive modal launchers
  - bottom action bar and progress/status surfaces
  - local video picker state and helper logic

Target owner / target boundary:

- a thin `DiscoveryPage` screen shell plus focused extracted presentation surfaces
- extracted surfaces must consume explicit inputs only
- extracted surfaces must not own feature truth
- `DiscoveryPage` must not become a new launcher/coordinator hub after extraction
- already-extracted owners and boundaries stay external and authoritative

Read switch point:

- the first production read path to switch is the side-menu/video-link surface currently assembled inline in `DiscoveryPage.build()`
- reads over:
  - `VideoLinkSessionBoundary`
  - local video picker state
  - menu action callbacks
  should move into an extracted dedicated surface instead of living in the monolithic page body

Write switch point:

- the first production launcher path to switch is the video-link/add-share/device-actions entry cluster:
  - `_publishSelectedVideoLink()`
  - `_toggleVideoLinkServer(...)`
  - `_openAddShareMenu()`
  - `_openDeviceActionsMenu(...)`
- these must stop living inline in the giant page file and move with their extracted presentation surfaces without reintroducing callback lattices

Forbidden writers:

- `DiscoveryPage`
- extracted widgets/sheets/helpers
- page-local state holding feature truth
- helper facades or launcher hubs acting as hidden feature owners

Forbidden dual-write paths:

- monolithic inline page section plus extracted surface both active for the same production flow
- old page-local state plus extracted surface input both acting as truth for the same UI concern
- split routing where `DiscoveryPage` still coordinates feature behavior while the extracted surface also starts doing so

Expected consumers of the future split:

- `DiscoveryPage` as thin shell only
- extracted sections/sheets/cards with explicit dependencies
- discovery entry smoke tests and any dedicated launch-flow widget tests added in PR2/PR3

Files PR2 will need to change:

Must change:

- `lib/features/discovery/presentation/discovery_page.dart`

Likely change:

- new supporting presentation files under `lib/features/discovery/presentation/`
- `test/smoke_test.dart`
- any new or updated widget/smoke tests for discovery launch flows

### PR1 conclusion

- PR2 is unblocked.
- The target page split is explicit enough for a non-speculative extraction.
- No blocker from `05_files_part_graph_removal.md` or `10_architecture_guard_and_regression_hardening.md` was found.
- The seam definition avoids creating a new presentation god-object or launcher hub.
- The seam definition keeps extracted owners external and authoritative.

## Completion proof

- `DiscoveryPage` shrinks materially
- major surfaces live in dedicated presentation files
- no feature truth moves back into page-local state
- feature-entry smoke coverage stays green
