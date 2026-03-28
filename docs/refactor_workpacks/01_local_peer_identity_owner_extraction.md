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

## PR1 Inventory Result

PR1 for this workpack is inventory-only.
No owner handoff happens here.
The purpose of this note is to freeze the seam contract so PR2 can execute without guessing.

### Production read paths found

- `lib/features/discovery/data/friend_repository.dart`
  - `loadOrCreateLocalPeerId()` reads `AppDatabase.appSettingsTable` where `setting_key = 'local_peer_id'`
- `lib/features/discovery/application/discovery_controller.dart`
  - `start()` reads the current value via `_friendRepository.loadOrCreateLocalPeerId()`
  - `localPeerId` exposes the controller-side cached mirror
  - `_resolveLocalDeviceMac()` reads `_localPeerId` to derive the stable fallback MAC seed
  - `start()` passes `_localPeerId` into `LanDiscoveryService.start(...)`
- `lib/features/discovery/data/lan_discovery_service.dart`
  - `start()` trims and stores the injected `localPeerId`
  - `_sendDiscoveryPing(...)` reads `_localPeerId` and encodes it into outbound discovery packets
  - the discover-response path also reads `_localPeerId` and encodes it into response packets
- `lib/features/discovery/data/lan_packet_codec.dart`
  - `encodeDiscoveryRequest(...)`
  - `encodeDiscoveryResponse(...)`
  - `_encodeDiscoveryPacket(...)`
  - these are pass-through serializers for the already-loaded local peer ID

### Production write/create paths found

- `lib/features/discovery/data/friend_repository.dart`
  - `loadOrCreateLocalPeerId()` is the only production create/write path found in `lib/`
  - if `local_peer_id` row is missing or blank, it generates a new `LN-...` value and writes it into `app_settings`
- No second production writer was found.
- No direct SQL write to `local_peer_id` was found outside `FriendRepository`.

### Test coupling inspected

Semantic and persistence coverage:

- `test/friend_repository_test.dart`
  - locks current `app_settings` key semantics and trimmed reuse behavior
- `test/settings_store_test.dart`
  - locks coexistence between settings rows and an existing `local_peer_id` row
- `test/discovery_controller_settings_store_test.dart`
  - locks that settings mutations do not clobber `local_peer_id`

Non-owner test coupling that only treats `localPeerId` as an input parameter:

- `test/lan_packet_codec_test.dart`
- `test/lan_discovery_service_contract_test.dart`
- `test/lan_discovery_service_packet_codec_test.dart`
- `test/lan_discovery_service_protocol_handlers_test.dart`
- `test/lan_discovery_service_transport_adapter_test.dart`

Builder/helper coupling likely affected by PR2 constructor wiring:

- `test/test_support/test_discovery_controller.dart`
- `test/discovery_controller_remote_share_browser_test.dart`
- `test/discovery_controller_remote_clipboard_projection_store_test.dart`
- `test/transfer_session_coordinator_test.dart`
- other `test/discovery_controller_*` and `test/discovery_read_model_test.dart` builders that still inject `FriendRepository` into `DiscoveryController`

### PR2 Seam Contract

- `Legacy owner`
  - `FriendRepository.loadOrCreateLocalPeerId()` plus the controller-side startup mirror `_localPeerId`
- `Target owner`
  - `LocalPeerIdentityStore`
  - narrow boundary that owns load/create/read of `local_peer_id` while preserving the current persisted key semantics in `app_settings`
- `Read switch point`
  - `DiscoveryController.start()` stops reading `FriendRepository.loadOrCreateLocalPeerId()`
  - startup and composition read `LocalPeerIdentityStore` instead
  - `LanDiscoveryService` continues to consume an injected string; it does not become the owner
- `Write switch point`
  - only `LocalPeerIdentityStore` may create or update `app_settings.setting_key = 'local_peer_id'`
  - `FriendRepository` must stop touching that row on the production path
- `Forbidden writers`
  - `FriendRepository`
  - `DiscoveryController`
  - `DiscoveryPageEntry`
  - widgets
  - compatibility helpers
  - direct SQL writes to `local_peer_id` outside the target boundary
- `Forbidden dual-write paths`
  - `LocalPeerIdentityStore` + `FriendRepository`
  - `LocalPeerIdentityStore` + controller/composition direct SQL
  - `LocalPeerIdentityStore` + `SettingsStore` writing the same key
- `Expected consumers of the future local identity boundary`
  - `DiscoveryController` startup
  - `DiscoveryController._resolveLocalDeviceMac()`
  - `LanDiscoveryService.start(...)` through injected value
  - discovery app composition and test builders
- `Files PR2 will need to change`
  - `lib/features/discovery/application/discovery_controller.dart`
  - `lib/features/discovery/data/friend_repository.dart`
  - `lib/app/discovery_page_entry.dart`
  - `lib/features/discovery/application/local_peer_identity_store.dart` (new)
  - `test/friend_repository_test.dart`
  - `test/settings_store_test.dart`
  - `test/discovery_controller_settings_store_test.dart`
  - `test/test_support/test_discovery_controller.dart`
  - likely discovery-controller builder tests that currently inject `FriendRepository` only because of local identity startup

### PR1 Conclusion

- PR2 is unblocked.
- The seam is explicit enough for an honest owner handoff.
- No code path was switched in PR1.
