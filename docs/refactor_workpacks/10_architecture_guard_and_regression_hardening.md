# Workpack 10: Architecture Guard and Regression Hardening

## Purpose

Turn the post-refactor architecture into an enforceable baseline by adding dedicated guard tests and restoring weak or missing entry-flow coverage.

## Why This Exists Now

Current evidence:

- there is no strong automated guard against reintroducing:
  - temporary bridges
  - callback backchannels
  - critical `part / part of` seams
  - direct repository bypasses around extracted owners
- some critical feature-entry proof still relies mainly on smoke coverage and full-suite confidence

## In Scope

- architecture guard tests
- widget/smoke coverage for discovery, files, clipboard, history, and remote-share entry flows touched by the new plan
- documentation or test helpers needed to keep guardrails cheap to run

## Out of Scope

- new owner extraction
- protocol or storage contract changes
- product UX redesign

## Target State

- prohibited architectural patterns fail fast in tests
- critical entry flows have explicit regression coverage
- future work cannot quietly reintroduce bridges, callback lattices, or hidden ownership hubs

## Pull Request Cycle

1. Inventory the architectural patterns that must now stay forbidden.
2. Add targeted guard tests and restore weak entry-flow coverage.
3. Delete obsolete test assumptions tied to the old tactical backlog.
4. Run the full suite, then `flutter analyze` and `flutter test`.

## Dependencies

- `01_local_peer_identity_owner_extraction.md`
- `03_discovery_page_surface_split.md`
- `04_shared_cache_maintenance_contract_cutover.md`
- `05_files_part_graph_removal.md`
- `06_remote_share_media_projection_cleanup.md`
- `07_shared_folder_cache_repository_split.md`
- `08_transfer_video_link_separation.md`
- `09_protocol_codec_family_decomposition.md`

## Required Test Gates

- `GATE-07`
- `GATE-08`

## Completion Proof

- dedicated guard tests fail on prohibited bridges, callback lattices, `part` regressions, and owner bypasses
- critical entry-flow coverage is explicit instead of implied
- full suite remains green
