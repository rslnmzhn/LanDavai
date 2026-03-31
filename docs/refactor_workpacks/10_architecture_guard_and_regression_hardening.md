# Workpack 10: Architecture Guard and Regression Hardening

## Purpose

Lock the post-refactor baseline with dedicated architecture guard tests and
explicit UI regression coverage for weak entry flows.

## Status

Open (partial).

## Target State

- GATE-07 architecture guards fail fast on forbidden residue
- weak entry flows have explicit behavior-level UI coverage

## Required Test Gates

- `GATE-07`
- `GATE-08`

## Progress (Current Baseline)

Completed:

- PR1 inventory freeze (documented)
- PR2 architecture guard suite exists:
  - `test/architecture_guard_test.dart`
- PR3A stable entry-flow coverage exists:
  - settings/clipboard/history-empty/device-actions/video-link side menu in
    `test/smoke_test.dart`
- shared-cache recache/remove UI entry proof:
  - `test/blocked_entry_flow_regression_test.dart`

Still missing UI coverage:

- discovery -> files launch
- files/viewer entry survivability
- remote-share preview/viewer launch
- history populated/open-folder action survivability

## Completion Proof (Target)

- all remaining weak flows above have explicit widget/smoke coverage
- guard suite and full regression remain green
