# Workpack 05: Files Part Graph Removal

## Purpose

Remove the files presentation `part / part of` cluster so explorer and viewer
code use explicit imports only.

## Status

Completed.

## Target State (Baseline)

- no `part / part of` under files presentation
- explorer widgets, viewer surface, and support types are in explicit files
- `LocalFileViewerPage` is standalone importable

## Dependencies

- `04_shared_cache_maintenance_contract_cutover.md`

## Required Test Gates

- `GATE-03`
- `GATE-07`
- `GATE-08`

## Completion Proof (Current Baseline)

- files presentation has explicit imports only:
  - `lib/features/files/presentation/file_explorer_page.dart`
  - `lib/features/files/presentation/file_explorer/*.dart`
- architecture guard forbids `part / part of` under `lib/`:
  - `test/architecture_guard_test.dart`
