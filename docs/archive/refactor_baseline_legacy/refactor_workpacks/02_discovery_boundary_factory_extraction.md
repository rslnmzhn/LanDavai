# Workpack 02: Discovery Boundary Factory Extraction

## Purpose

Move discovery graph assembly out of `DiscoveryPageEntry` widget lifecycle into
an explicit app-layer composition surface.

## Status

Completed.

## Target State (Baseline)

- discovery graph built in app-layer composition
- `DiscoveryPageEntry` is a thin host
- lifecycle ownership is explicit outside the widget

## Dependencies

- `01_local_peer_identity_owner_extraction.md`
- `04_shared_cache_maintenance_contract_cutover.md`
- `06_remote_share_media_projection_cleanup.md`
- `08_transfer_video_link_separation.md`

## Required Test Gates

- `GATE-03`
- `GATE-08`

## Completion Proof (Current Baseline)

- composition lives in `lib/app/discovery/discovery_composition.dart`
- `DiscoveryPageEntry` uses injected composition result and does not assemble
  the graph inline
- smoke tests cover entry boot:
  - `test/smoke_test.dart`
