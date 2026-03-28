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
