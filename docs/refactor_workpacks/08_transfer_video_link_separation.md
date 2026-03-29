# Workpack 08: Transfer and Video-Link Separation

## Purpose

Separate the remaining transfer-session shell concerns from the video-link watch/share seam so they cannot collapse back into one broad runtime flow.

## Why This Exists Now

Current evidence:

- `TransferSessionCoordinator` is still large
- `VideoLinkShareService.activeSession` remains a separate seam
- discovery/page shells still host both transfer entry and watch-link entry concerns

The tactical backlog explicitly avoided absorbing video-link session into transfer ownership.

## In Scope

- `lib/features/transfer/application/transfer_session_coordinator.dart`
- `lib/features/transfer/data/video_link_share_service.dart`
- `lib/features/discovery/application/discovery_controller.dart`
- `lib/features/discovery/presentation/discovery_page.dart`
- `lib/app/discovery_page_entry.dart`
- tests covering transfer continuity and video-link flows

## Out of Scope

- protocol codec rewrite
- transfer storage semantic changes
- preview or files owner redesign

## Target State

- transfer coordinator stays transfer-only
- video-link flow gets a clearer separate boundary or entry surface
- discovery/controller/page shells stop mixing watch-link orchestration into transfer shell logic

## Pull Request Cycle

1. Inventory every place where transfer flow and video-link flow still share shell logic.
2. Introduce the explicit video-link boundary or entry surface while keeping `VideoLinkShareService.activeSession` separate from transfer truth.
3. Remove mixed routing from discovery/controller/page surfaces.
4. Run transfer continuity and video-link regressions, then `flutter analyze` and `flutter test`.

## Dependencies

- none beyond the current baseline

## Required Test Gates

- `GATE-05`
- `GATE-08`

## Completion Proof

- `TransferSessionCoordinator` no longer mixes watch-link shell responsibilities
- `VideoLinkShareService.activeSession` remains separate and explicit
- transfer and video-link flows both remain green

## PR1 Inventory Result

### Baseline Confirmed

- `TransferSessionCoordinator` still owns transfer/session truth only
- `VideoLinkShareService.activeSession` remains a separate video-link seam
- no production path was found that merges video-link session truth into transfer truth
- current overlap is shell-level routing and projection inside discovery/controller/page surfaces

### Production Shared-Shell Inventory

#### Transfer-only canonical owner-backed paths

- `lib/features/transfer/application/transfer_session_coordinator.dart`
  - `sendFilesToDevice(...)`
  - `requestDownloadFromRemoteFiles(...)`
  - `requestRemoteFilePreview(...)`
  - `respondToTransferRequest(...)`
  - `handleTransferRequestEvent(...)`
  - `handleTransferDecisionEvent(...)`
  - `handleDownloadRequestEvent(...)`
  - transfer status reads:
    - `incomingRequests`
    - `isUploading`
    - `isDownloading`
    - `uploadProgress`
    - `downloadProgress`
    - `uploadEta`
    - `downloadEta`
    - `takePendingNotice()`
- classification:
  - production path
  - canonical transfer owner-backed behavior
  - no watch-link responsibilities found here

#### Video-link-only canonical service path

- `lib/features/transfer/data/video_link_share_service.dart`
  - `activeSession`
  - `publish(...)`
  - `stop()`
  - `VideoLinkShareSession.buildWatchUrl(...)`
- classification:
  - production path
  - canonical video-link runtime/service seam
  - not treated as transfer truth in the service itself

#### Mixed shell routing in `DiscoveryController`

- `lib/features/discovery/application/discovery_controller.dart`
  - `_videoLinkShareSession`
    - operation: session relay / local mirror
    - initiator: controller publish/stop methods
    - downstream target: page/video-link UI reads
    - classification: production shell coupling residue
  - `videoLinkShareSession`
    - operation: read
    - initiator: `DiscoveryPage`, `_VideoLinkServerCard`
    - downstream target: controller mirror
    - classification: production shell coupling residue
  - `videoLinkWatchUrl`
    - operation: read / derived status projection
    - initiator: `DiscoveryPage`, `_VideoLinkServerCard`
    - downstream target: controller mirror + `_localIp`
    - classification: production shell coupling residue
  - `publishVideoLinkShare(...)`
    - operation: write / command dispatch
    - initiator: `DiscoveryPage._publishSelectedVideoLink()`
    - downstream target: `VideoLinkShareService.publish(...)`
    - classification: production shell coupling residue
  - `stopVideoLinkShare()`
    - operation: write / command dispatch
    - initiator: `DiscoveryPage._toggleVideoLinkServer(false)`
    - downstream target: `VideoLinkShareService.stop()`
    - classification: production shell coupling residue
  - `setVideoLinkPassword(...)`
    - operation: command dispatch
    - initiator: settings sheet
    - downstream target: `SettingsStore`
    - classification: discovery/settings shell, not video-link session truth
  - `sendFilesToSelectedDevice()`
    - operation: command dispatch
    - initiator: discovery action bar
    - downstream target: `TransferSessionCoordinator.sendFilesToDevice(...)`
    - classification: production transfer shell entry
  - `_handleTransferSessionCoordinatorChanged()`
    - operation: status observation / notice relay
    - initiator: transfer coordinator listener
    - downstream target: controller info/error shell
    - classification: production transfer shell coupling
  - constructor wiring
    - injects both `VideoLinkShareService` and `TransferSessionCoordinator`
    - classification: mixed shell composition inside controller

#### Mixed shell routing in `DiscoveryPage`

- `lib/features/discovery/presentation/discovery_page.dart`
  - `_publishSelectedVideoLink()`
    - operation: command dispatch
    - initiator: video-link UI
    - downstream target: `DiscoveryController.publishVideoLinkShare(...)`
    - classification: production shell coupling residue
  - `_toggleVideoLinkServer(...)`
    - operation: entry routing / status observation / command dispatch
    - initiator: side menu toggle
    - downstream target: controller video-link getter + controller stop/publish commands
    - classification: production shell coupling residue
  - `_VideoLinkServerCard`
    - reads `controller.videoLinkShareSession`
    - reads `controller.videoLinkWatchUrl`
    - classification: production shell coupling residue
  - side menu copy-link actions
    - read `controller.videoLinkWatchUrl`
    - classification: production shell coupling residue
  - transfer progress and receive surfaces
    - `_TransferProgressCard(transferSessionCoordinator: ...)`
    - `_ReceivePanelSheet(transferSessionCoordinator: ...)`
    - `requestRemoteFilePreview(...)`
    - `requestDownloadFromRemoteFiles(...)`
    - classification: production transfer owner-backed behavior
  - send action
    - `onSend: _controller.sendFilesToSelectedDevice`
    - classification: thin transfer shell entry through controller

#### Mixed composition in `DiscoveryPageEntry`

- `lib/app/discovery_page_entry.dart`
  - constructs `TransferSessionCoordinator`
  - constructs `VideoLinkShareService()`
  - injects coordinator directly into `DiscoveryPage`
  - injects video-link service only through `DiscoveryController`
  - classification:
    - production composition surface
    - mixed entry wiring that still favors controller shell for video-link while transfer already has an explicit boundary

### `VideoLinkShareService.activeSession` Usage Inventory

- direct production reads of `activeSession`
  - none found outside `VideoLinkShareService` itself
- direct production writes/replacements of video-link session
  - `VideoLinkShareService.publish(...)`
  - `VideoLinkShareService.stop()`
- effective production read path today
  - `DiscoveryController._videoLinkShareSession` mirror
  - `DiscoveryController.videoLinkShareSession`
  - `DiscoveryController.videoLinkWatchUrl`
  - `DiscoveryPage` / `_VideoLinkServerCard` / side-menu copy-link actions
- classification
  - `activeSession` remains separate video-link truth
  - the current problem is not transfer ownership drift inside the service
  - the current problem is controller/page shell mirroring and routing around that truth

### Test/Support Coupling Inspected

- `test/transfer_session_coordinator_test.dart`
  - transfer seam continuity proof
  - includes controller harness construction with `VideoLinkShareService()`
  - also asserts `controller.videoLinkShareSession` remains null in a transfer path
- `test/video_link_share_service_test.dart`
  - canonical service continuity proof for watch-link publish/stop/auth/stream behavior
- `test/smoke_test.dart`
  - discovery entry wiring proof
- `test/test_support/test_discovery_controller.dart`
  - harness wiring currently injects both transfer coordinator and video-link service through controller construction
- `test/discovery_controller_settings_store_test.dart`
  - only settings/password continuity
  - not evidence of transfer/video-link ownership overlap
- constructor-only coupling also exists in:
  - `test/discovery_controller_device_registry_test.dart`
  - `test/discovery_controller_internet_peer_endpoint_store_test.dart`
  - `test/discovery_controller_remote_clipboard_projection_store_test.dart`
  - `test/discovery_controller_remote_share_browser_test.dart`
  - `test/discovery_controller_trusted_lan_peer_store_test.dart`
  - `test/discovery_read_model_test.dart`

### PR2 Seam Contract

#### Legacy owner / legacy route

- transfer truth remains correctly owned by `TransferSessionCoordinator`
- video-link runtime truth remains in `VideoLinkShareService.activeSession`
- the mixed legacy route is the discovery shell around them:
  - `DiscoveryPage`
  - `DiscoveryController`
  - controller-local `_videoLinkShareSession` mirror
  - controller-derived `videoLinkWatchUrl`
  - controller video-link command shells
  - composition that injects transfer explicitly but routes video-link through controller only

#### Target owner / target boundary

- introduce an explicit `VideoLinkSessionBoundary`
- narrow responsibilities only:
  - publish video-link share
  - stop active video-link share
  - expose active video-link session projection
  - expose watch URL projection
- constraints:
  - `TransferSessionCoordinator` remains transfer-only
  - `VideoLinkShareService.activeSession` remains separate from transfer truth
  - `DiscoveryController` and `DiscoveryPage` must not become fallback owners
  - settings/password truth remains in `SettingsStore`, not in the new boundary

#### Read switch point

- first production read/status path to switch:
  - `DiscoveryPage`
  - `_VideoLinkServerCard`
  - side-menu copy-link actions
- these must stop reading:
  - `DiscoveryController.videoLinkShareSession`
  - `DiscoveryController.videoLinkWatchUrl`
- they must read the future `VideoLinkSessionBoundary` instead

#### Write switch point

- first production command/session path to switch:
  - `DiscoveryPage._publishSelectedVideoLink()`
  - `DiscoveryPage._toggleVideoLinkServer(...)`
- these must stop dispatching through:
  - `DiscoveryController.publishVideoLinkShare(...)`
  - `DiscoveryController.stopVideoLinkShare()`
- they must dispatch to the future `VideoLinkSessionBoundary` instead

#### Forbidden writers

- `DiscoveryController`
- `DiscoveryPage`
- widgets
- helper facades
- `TransferSessionCoordinator`
- page-local callback wrappers

#### Forbidden dual-write / dual-route paths

- new boundary + controller mirror `_videoLinkShareSession`
- new boundary + `DiscoveryController.publishVideoLinkShare(...)`
- new boundary + `DiscoveryController.stopVideoLinkShare()`
- new boundary watch URL projection + `DiscoveryController.videoLinkWatchUrl`
- page reading boundary session while controller still remains a parallel video-link read truth

#### Expected consumers of the future separated boundary

- video-link consumers:
  - `DiscoveryPage` video-link entry helpers
  - `_VideoLinkServerCard`
  - side-menu copy-link/toggle surfaces
- transfer consumers remain:
  - action bar send flow
  - `_TransferProgressCard`
  - `_ReceivePanelSheet`
  - transfer preview/download flows
- composition/injection sites:
  - `DiscoveryPageEntry`
  - test harnesses that currently build `DiscoveryController` with `VideoLinkShareService`

#### Files PR2 will need to change

Must-change:

- `lib/features/discovery/application/discovery_controller.dart`
- `lib/features/discovery/presentation/discovery_page.dart`
- `lib/app/discovery_page_entry.dart`
- new boundary file for `VideoLinkSessionBoundary`
- `test/test_support/test_discovery_controller.dart`
- `test/smoke_test.dart`

Likely-change:

- `test/transfer_session_coordinator_test.dart`
- discovery controller builder tests that currently inject `VideoLinkShareService()` only for constructor completeness
- any dedicated discovery-page/widget coverage added for video-link entry after the cutover

### PR1 Assessment

- PR2 is unblocked
- the target separation boundary is explicit enough for a non-speculative cutover
- no blocker was found from `02`, `03`, or `09`
- the seam definition does not require making `DiscoveryController` or `DiscoveryPage` a fallback owner again
