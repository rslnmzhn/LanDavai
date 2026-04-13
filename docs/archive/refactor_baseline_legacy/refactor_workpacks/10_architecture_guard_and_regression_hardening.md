# Workpack 10: Architecture Guard and Regression Hardening

## Purpose

Lock the post-refactor baseline with dedicated architecture guard tests and
explicit UI regression coverage for weak entry flows.

## Status

Completed.

## Target State

- GATE-07 architecture guards fail fast on forbidden residue
- weak entry flows have explicit behavior-level UI coverage

## Required Test Gates

- `GATE-07`
- `GATE-08`

Previously remaining (now resolved):

- discovery -> files launch: coverage gap + harness gap
- files/viewer entry survivability: coverage gap + harness gap
- remote-share preview/viewer launch: coverage gap + harness gap
- history populated/open-folder action survivability: coverage gap

## Completion Proof

- All four UI flows above are covered by behavior-level widget tests.
- GATE-07 passes (`test/architecture_guard_test.dart`).
- GATE-08 passes (`flutter analyze`, `flutter test`).
- No production architecture changes were required.
