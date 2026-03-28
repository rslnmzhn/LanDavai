# Workpack 09: Protocol Codec Family Decomposition

## Purpose

Split the remaining large protocol codec surface into smaller codec families without drifting wire semantics.

## Why This Exists Now

Current evidence:

- `lan_packet_codec.dart` is still one of the largest files in the repo
- protocol split happened, but codec responsibilities are still concentrated in one large module
- future protocol changes still risk broad diffs in one file

## In Scope

- `lib/features/discovery/data/lan_packet_codec.dart`
- adjacent protocol codec helpers or protocol tests
- any codec-family files created under the same protocol layer

## Out of Scope

- packet identifier changes
- envelope semantic changes
- transport lifecycle redesign

## Target State

- codec logic is split by packet family or scenario family
- packet identifiers and decode semantics remain unchanged
- protocol layer stays protocol-only

## Pull Request Cycle

1. Inventory codec families and lock current parity with tests.
2. Split codec responsibilities into smaller files or modules by packet family.
3. Delete the monolithic codec surface or reduce it to a thin export shell.
4. Run protocol compatibility tests, then `flutter analyze` and `flutter test`.

## Dependencies

- `08_transfer_video_link_separation.md`

## Required Test Gates

- `GATE-06`
- `GATE-08`

## Completion Proof

- protocol codec logic is no longer concentrated in one large file
- packet identifiers and envelope semantics do not drift
- protocol tests stay green
