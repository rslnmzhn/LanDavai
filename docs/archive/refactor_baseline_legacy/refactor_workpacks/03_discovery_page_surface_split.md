# Workpack 03: Discovery Page Surface Split

## Purpose

Split the monolithic `DiscoveryPage` into dedicated presentation surfaces while
keeping owner truth external.

## Status

Completed.

## Target State (Baseline)

- `DiscoveryPage` is a thin screen shell
- major surfaces live in dedicated files under
  `lib/features/discovery/presentation/`

## Dependencies

- `02_discovery_boundary_factory_extraction.md`
- `04_shared_cache_maintenance_contract_cutover.md`
- `08_transfer_video_link_separation.md`

## Required Test Gates

- `GATE-03`
- `GATE-08`

## Completion Proof (Current Baseline)

Dedicated surfaces now exist, including:

- `discovery_side_menu_surface.dart`
- `discovery_action_bar.dart`
- `discovery_device_list_section.dart`
- `discovery_device_actions.dart`
- `discovery_add_share_sheet.dart`
- `discovery_history_sheet.dart`
- `discovery_friends_sheet.dart`
- `discovery_receive_panel_sheet.dart`

Smoke coverage for the main entry and menu flows:

- `test/smoke_test.dart`
