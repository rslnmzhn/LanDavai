# Workpack 01: Local Peer Identity Owner Extraction

## Purpose

Вытащить `local_peer_id` из `FriendRepository` и startup path `DiscoveryController` в отдельный boundary.
Это не redesign friend endpoints.
Это узкий ownership handoff для local identity seam.

## Current evidence

- `lib/features/discovery/data/friend_repository.dart`
  - `_localPeerIdKey`
  - `loadOrCreateLocalPeerId()`
- `lib/features/discovery/application/discovery_controller.dart`
  - `start()` still calls `_friendRepository.loadOrCreateLocalPeerId()`
- tests still codify this old coupling:
  - `test/friend_repository_test.dart`
  - `test/settings_store_test.dart`
  - `test/discovery_controller_settings_store_test.dart`

## Target state

- dedicated local identity boundary owns load/create/read of local peer ID
- `FriendRepository` becomes friend-endpoint only
- `DiscoveryController`, discovery composition, and any protocol sender path consume the new boundary instead of `FriendRepository`
- current persisted key semantics stay compatible unless a later dedicated migration explicitly changes them

## In scope

- `lib/features/discovery/data/friend_repository.dart`
- `lib/features/discovery/application/discovery_controller.dart`
- `lib/app/discovery_page_entry.dart`
- new local identity boundary under `lib/features/discovery/application/` or another narrow app-layer location
- affected tests around local peer identity and settings/friend persistence

## Out of scope

- internet peer endpoint ownership redo
- settings redesign
- discovery page redesign
- protocol semantics changes

## Pull Request Cycle

1. Inventory every production read/write of `local_peer_id`.
2. Introduce the dedicated local identity boundary and wire it into composition.
3. Switch controller and other production paths to the new boundary.
4. Downgrade `FriendRepository` to friend-only responsibility.
5. Run `flutter analyze`, focused persistence tests, and full `flutter test`.

## Required test gates

- `GATE-01`
- `GATE-08`

## Completion proof

- no production path calls `FriendRepository.loadOrCreateLocalPeerId()`
- `FriendRepository` no longer owns `local_peer_id` as business truth
- `DiscoveryController` startup reads local identity only through the dedicated boundary
- analyzer and tests stay green
