# 06 Remote-Share Media Projection Cleanup

Read first:
- `AGENTS.md`
- `refactor_context.md`
- `docs/refactor_master_plan.md`
- `docs/refactor_workpacks/00_index.md`

## Purpose

Remove controller-side remote-share media residue so remote browse thumbnails and related media projection stop bypassing existing owners through repository calls and manual notification glue.

## Current Problem / Evidence

- `lib/features/discovery/application/discovery_controller.dart` still performs direct thumbnail IO through `SharedFolderCacheRepository`
- controller still manually nudges `RemoteShareBrowser` notifications after some media-related updates
- remote browse truth is extracted, but media projection responsibilities are still split between controller, browser, preview owner, and repository helpers

## Target Boundary

- remote browse truth remains in `RemoteShareBrowser`
- preview artifact truth remains in `PreviewCacheOwner`
- a narrow remote-share media projection path owns thumbnail/media updates without controller-side repository bypasses
- controller no longer drives browser notifications for media updates

## In Scope

- `lib/features/discovery/application/discovery_controller.dart`
- `lib/features/discovery/application/remote_share_browser.dart`
- `lib/features/files/application/preview_cache_owner.dart`
- `lib/features/transfer/data/shared_folder_cache_repository.dart`
- any new narrow media projection helper/boundary needed by the cutover

## Out Of Scope

- remote browse session ownership redesign
- preview owner redesign
- shared-cache metadata/index ownership changes
- video-link session work

## Dependencies

- depends on `04`, because files/shared-cache maintenance needs to stop using callback residue first

## Pull Request Cycle

### PR1

- inventory every controller-side remote thumbnail/media path
- define the boundary that will own remote media projection behavior

### PR2

- switch controller-side repository IO and media update flows to the new boundary
- keep `RemoteShareBrowser` and `PreviewCacheOwner` responsibilities explicit and separate

### PR3

- delete manual notify glue and obsolete controller-side helpers
- run remote-share media and preview regressions

## Required Tests

- remote share browser regression tests
- preview-related remote file tests in covered scope
- shared-cache media continuity tests if thumbnail paths move
- `flutter analyze`
- `flutter test`

## Completion Proof

- controller no longer performs remote-share thumbnail repository IO directly
- browser/media updates no longer rely on controller-side manual notification nudges
- remote-share media projection is routed through an explicit owner-backed path

## PR1 Inventory Result

### Prerequisite Check

- dependency on `04` is satisfied in the current baseline
- no production `SharedCacheCatalogBridge` or files/shared-cache callback residue remains on the remote-share media path
- `RemoteShareBrowser` still owns remote browse/session truth
- `PreviewCacheOwner` still owns preview artifact lifecycle
- `DiscoveryController` is not supposed to own remote-share media IO, but still does in the paths listed below

### Production Media/Thumbnail Read Paths

#### Owner-backed paths already in place

- `lib/features/discovery/application/remote_share_browser.dart`
  - `currentBrowseProjection`
  - `_buildFileChoices(...)`
  - `previewPathFor(...)`
  - operation:
    - read
    - projection
  - initiator:
    - `DiscoveryPage`
    - browse UI consumers
  - downstream target:
    - `RemoteShareBrowser` preview-path map
  - classification:
    - owner-backed

- `lib/features/discovery/presentation/discovery_page.dart`
  - `_RemoteFilePreview`
  - operation:
    - read
    - projection consumption
  - initiator:
    - remote browse UI
  - downstream target:
    - `RemoteBrowseFileChoice.previewPath`
  - classification:
    - owner-backed UI read

- `lib/features/discovery/presentation/discovery_page.dart`
  - `_previewRemoteFile(...)`
  - operation:
    - command dispatch
    - read of returned preview path
  - initiator:
    - remote file preview action
  - downstream target:
    - `TransferSessionCoordinator.requestRemoteFilePreview(...)`
    - `PreviewCacheOwner`
  - classification:
    - owner-backed preview flow

- `lib/features/files/application/preview_cache_owner.dart`
  - `buildCompressedPreviewFilesForCache(...)`
  - `loadAudioCover(...)`
  - `cleanupPreviewArtifacts(...)`
  - operation:
    - preview artifact read/write
    - lifecycle
  - classification:
    - owner-backed preview lifecycle

#### Controller-side direct reads and projection logic

- `lib/features/discovery/application/discovery_controller.dart`
  - `_syncRemoteThumbnails(...)`
  - operation:
    - read
    - IO
    - projection
  - initiator:
    - `_handleShareCatalog(...)`
  - downstream target:
    - `RemoteShareBrowser.previewPathFor(...)`
    - `SharedFolderCacheRepository.resolveReceiverThumbnailPath(...)`
  - classification:
    - controller bypass

- `lib/features/discovery/application/discovery_controller.dart`
  - `_handleThumbnailSyncRequest(...)`
  - operation:
    - read
    - IO
  - initiator:
    - thumbnail sync protocol event
  - downstream target:
    - `SharedCacheIndexStore.readIndexEntries(...)`
    - `SharedFolderCacheRepository.readOwnerThumbnailBytes(...)`
    - `LanDiscoveryService.sendThumbnailPacket(...)`
  - classification:
    - controller bypass

### Production Media/Thumbnail Write and IO Paths

- `lib/features/discovery/application/discovery_controller.dart`
  - `_handleThumbnailPacket(...)`
  - operation:
    - write
    - IO
    - projection update
  - initiator:
    - thumbnail packet protocol event
  - downstream target:
    - `SharedFolderCacheRepository.saveReceiverThumbnailBytes(...)`
    - `RemoteShareBrowser.recordPreviewPath(...)`
  - classification:
    - controller bypass

- `lib/features/discovery/application/discovery_controller.dart`
  - `_syncRemoteThumbnails(...)`
  - operation:
    - write
    - projection update
    - notify/relay
  - initiator:
    - `_handleShareCatalog(...)`
  - downstream target:
    - `RemoteShareBrowser.recordPreviewPath(...)`
    - `LanDiscoveryService.sendThumbnailSyncRequest(...)`
    - `RemoteShareBrowser.notifyListeners()`
  - classification:
    - controller bypass
    - manual notify glue

- `lib/features/discovery/application/discovery_controller.dart`
  - `_handleShareCatalog(...)`
  - operation:
    - notify/relay
  - initiator:
    - share catalog protocol event
  - downstream target:
    - `RemoteShareBrowser.applyRemoteCatalog(...)`
    - then controller-triggered `_syncRemoteThumbnails(...)`
  - classification:
    - mixed route
    - owner-backed browse apply plus controller-side media follow-up

### Bypass Patterns Found

#### A) Controller IO bypass

- controller reads owner thumbnail bytes directly through `SharedFolderCacheRepository.readOwnerThumbnailBytes(...)`
- controller resolves cached receiver thumbnail paths directly through `SharedFolderCacheRepository.resolveReceiverThumbnailPath(...)`
- controller writes receiver thumbnail bytes directly through `SharedFolderCacheRepository.saveReceiverThumbnailBytes(...)`
- violated owner boundary:
  - controller is doing remote-share media IO that should not live in discovery shell state

#### B) Controller notify glue

- controller calls `RemoteShareBrowser.recordPreviewPath(...)` after repository IO
- controller manually calls `RemoteShareBrowser.notifyListeners()` in `_syncRemoteThumbnails(...)`
- violated owner boundary:
  - `RemoteShareBrowser` should own browse projection updates and notification timing for its preview-path projection

#### C) Mixed ownership around preview/media lifecycle

- `RemoteShareBrowser` owns the preview-path map used in remote browse projection
- `PreviewCacheOwner` owns preview artifacts for explicit preview/download flows
- controller currently sits in the middle for remote thumbnail sync/reuse and repository IO
- repository helpers and `ThumbnailCacheService` do storage work only, but controller currently acts like the policy owner over them

### Canonical Owner Paths Confirmed

- `RemoteShareBrowser`
  - owns remote browse/session truth
  - owns preview-path projection read model used by `RemoteBrowseFileChoice.previewPath`
  - already exposes the canonical read path consumed by `DiscoveryPage`

- `PreviewCacheOwner`
  - owns preview artifact lifecycle for explicit preview/download flows
  - already backs `TransferSessionCoordinator.requestRemoteFilePreview(...)`
  - does not currently own remote browse thumbnail sync/reuse

### PR2 Seam Contract

#### Legacy owner / route

- current broken route is:
  - `DiscoveryController._handleShareCatalog(...)`
  - `DiscoveryController._syncRemoteThumbnails(...)`
  - `DiscoveryController._handleThumbnailSyncRequest(...)`
  - `DiscoveryController._handleThumbnailPacket(...)`
- this route combines:
  - repository thumbnail IO
  - remote preview-path projection updates
  - manual `RemoteShareBrowser` notification glue

#### Target owner / boundary

- `RemoteShareBrowser` remains owner of remote browse truth and preview-path projection
- `PreviewCacheOwner` remains owner of explicit preview artifact lifecycle
- PR2 should introduce a narrow `RemoteShareMediaProjectionBoundary`
- that boundary should own only:
  - remote thumbnail sync/reuse IO orchestration
  - mapping repository/media results into `RemoteShareBrowser` projection updates
  - coordination of media-related notify timing for that projection
- constraints:
  - no new god-service
  - no re-ownership of browse session truth
  - no re-ownership of preview artifact lifecycle

#### Read switch point

- first controller read path to eliminate:
  - `DiscoveryController._syncRemoteThumbnails(...)`
- it must stop reading:
  - `RemoteShareBrowser.previewPathFor(...)`
  - `SharedFolderCacheRepository.resolveReceiverThumbnailPath(...)`
- those reads must move behind the new media projection boundary

#### Write switch point

- first controller write/IO paths to eliminate:
  - `DiscoveryController._handleThumbnailPacket(...)`
  - `DiscoveryController._handleThumbnailSyncRequest(...)`
- controller must stop:
  - writing receiver thumbnail bytes
  - reading owner thumbnail bytes for reply packets
  - directly updating `RemoteShareBrowser.recordPreviewPath(...)`

#### Forbidden writers

- `DiscoveryController`
- `DiscoveryPage`
- widgets
- `SharedFolderCacheRepository` and `ThumbnailCacheService` acting as policy owners

#### Forbidden dual-write paths

- controller + new boundary both doing thumbnail repository IO
- controller + new boundary both calling `RemoteShareBrowser.recordPreviewPath(...)`
- controller manual notify + boundary/owner notify on the same media update path
- controller-side preview-path reuse plus owner-backed preview-path reuse in parallel

#### Expected consumers

- UI reads remote preview/thumbnail state only from `RemoteShareBrowser.currentBrowseProjection`
- `DiscoveryController` may remain a protocol event ingress point only if it forwards to the new boundary and stops owning media IO/policy
- explicit preview open/download flows continue using `TransferSessionCoordinator` and `PreviewCacheOwner`

#### Files PR2 will change

Must-change:

- `lib/features/discovery/application/discovery_controller.dart`
- `lib/features/discovery/application/remote_share_browser.dart`
- preview-related remote-share code path introduced for the new boundary

Likely-change:

- `lib/features/transfer/data/shared_folder_cache_repository.dart`
- `lib/features/discovery/presentation/discovery_page.dart`
- tests covering remote-share browser projection and controller thumbnail handling

### Tests Inspected for PR2 Impact

- `test/remote_share_browser_test.dart`
- `test/preview_cache_owner_test.dart`
- `test/discovery_controller_remote_share_browser_test.dart`
- `test/transfer_session_coordinator_test.dart`
- `test/smoke_test.dart`

### PR1 Assessment

- PR2 is unblocked
- owner boundaries are clear enough for a non-speculative cutover
- there is no blocker dependency on `07`; `07` remains downstream infra cleanup after the media route is clarified
- the main ambiguity is not browser vs preview owner ownership drift
- the real seam is that remote browse thumbnail projection is still controller-owned glue between repository IO and `RemoteShareBrowser`, while `PreviewCacheOwner` remains separate for explicit preview artifacts
