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
