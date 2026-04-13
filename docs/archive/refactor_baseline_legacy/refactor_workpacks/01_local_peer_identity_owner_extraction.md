# Workpack 01: Local Peer Identity Owner Extraction

## Purpose

Move local peer identity ownership out of `FriendRepository` into a dedicated
boundary without changing persisted semantics.

## Status

Completed.

## Target State (Baseline)

- `LocalPeerIdentityStore` owns read/create/write of `local_peer_id`
- `FriendRepository` is friend-only
- `DiscoveryController` reads local identity via `LocalPeerIdentityStore`

## Dependencies

- none

## Required Test Gates

- `GATE-01`
- `GATE-08`

## Completion Proof (Current Baseline)

- `LocalPeerIdentityStore` exists and owns `local_peer_id`
  - `lib/features/discovery/application/local_peer_identity_store.dart`
- `FriendRepository` contains no local peer identity logic
  - `lib/features/discovery/data/friend_repository.dart`
- `DiscoveryController` loads the peer ID via `LocalPeerIdentityStore`
  - `lib/features/discovery/application/discovery_controller.dart`
- guard tests forbid regressions
  - `test/architecture_guard_test.dart`
