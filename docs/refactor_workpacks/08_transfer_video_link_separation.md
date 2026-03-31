# Workpack 08: Transfer and Video-Link Separation

## Purpose

Keep transfer session truth and video-link session truth separate and prevent
re-merging through discovery shell routes.

## Status

Completed.

## Target State (Baseline)

- transfer truth remains in `TransferSessionCoordinator`
- video-link session routed via `VideoLinkSessionBoundary`
- controller/page do not own or mirror video-link session truth

## Required Test Gates

- `GATE-05`
- `GATE-08`

## Completion Proof (Current Baseline)

- `VideoLinkSessionBoundary` exists and is used by the UI
- controller-side video-link mirrors/commands are forbidden by guard tests
  - `test/architecture_guard_test.dart`
- transfer and video-link tests remain green:
  - `test/transfer_session_coordinator_test.dart`
  - `test/video_link_session_boundary_test.dart`
