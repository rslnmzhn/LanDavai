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

## PR1 Inventory Result

### Baseline Confirmed

- `08_transfer_video_link_separation.md` is already satisfied.
- No video-link packet family was found in `lan_packet_codec.dart` or `lan_discovery_service.dart`.
- `LanDiscoveryService` already owns transport lifecycle and protocol-handler routing.
- Workpack `09` remains protocol-only and does not need storage, transport, or shell redesign.

### Production Codec Family Inventory

#### Presence / discovery family

- `LanDiscoveryPresencePacket`
- `encodeDiscoveryRequest(...)`
- `encodeDiscoveryResponse(...)`
- `decodeDiscoveryPacket(...)`
- `_encodeDiscoveryPacket(...)`
- `_tryDecodeDiscoveryPayload(...)`
- `_normalizeDiscoveryText(...)`
- `_resolveLocalDeviceType()`

#### Transfer family

- `TransferAnnouncementItem`
- `LanTransferRequestPacket`
- `LanTransferDecisionPacket`
- `encodeTransferRequest(...)`
- `encodeTransferDecision(...)`
- `_parseTransferRequestPacket(...)`
- `_parseTransferDecisionPacket(...)`

#### Friend family

- `LanFriendRequestPacket`
- `LanFriendResponsePacket`
- `encodeFriendRequest(...)`
- `encodeFriendResponse(...)`
- `_parseFriendRequestPacket(...)`
- `_parseFriendResponsePacket(...)`

#### Share / thumbnail family

- `SharedCatalogFileItem`
- `SharedCatalogEntryItem`
- `ThumbnailSyncItem`
- `LanShareQueryPacket`
- `LanShareCatalogPacket`
- `LanDownloadRequestPacket`
- `LanThumbnailSyncRequestPacket`
- `LanThumbnailPacket`
- `encodeShareQuery(...)`
- `encodeShareCatalog(...)`
- `fitShareCatalogEntries(...)`
- `encodeDownloadRequest(...)`
- `encodeThumbnailSyncRequest(...)`
- `encodeThumbnailPacket(...)`
- `_parseShareQueryPacket(...)`
- `_parseShareCatalogPacket(...)`
- `_parseDownloadRequestPacket(...)`
- `_parseThumbnailSyncRequestPacket(...)`
- `_parseThumbnailPacket(...)`

#### Clipboard family

- `ClipboardCatalogItem`
- `LanClipboardQueryPacket`
- `LanClipboardCatalogPacket`
- `encodeClipboardQuery(...)`
- `encodeClipboardCatalog(...)`
- `_parseClipboardQueryPacket(...)`
- `_parseClipboardCatalogPacket(...)`

#### Shared envelope / common helper cluster

- `EncodedLanPacket`
- `LanInboundPacket`
- packet prefix constants
- `protocolPrefixes`
- UDP packet and share-trim limits
- `encodeEnvelopeForTest(...)`
- `decodeEnvelopeForTest(...)`
- `_encodeEnvelopePacket(...)`
- `_decodeEnvelope(...)`

### Production Call Sites

- `LanDiscoveryService` is the only production codec runtime consumer.
- Outbound encode calls stay in:
  - discovery ping / response
  - transfer request / decision
  - friend request / response
  - share query / catalog / download / thumbnail
  - clipboard query / catalog
- Inbound decode stays in:
  - `LanDiscoveryService._handleIncomingDatagram(...)`
  - `LanPacketCodec.decodeIncomingPacket(...)`
- Application-level DTO consumers outside the codec file still import packet items from `lan_packet_codec.dart`:
  - `TransferSessionCoordinator`
  - `DiscoveryController`
  - `RemoteShareBrowser`
  - `RemoteShareMediaProjectionBoundary`
  - `RemoteClipboardProjectionStore`

### PR2 Seam Contract

#### Legacy owner / route

- `lan_packet_codec.dart` is the monolithic protocol codec surface.
- It currently owns packet DTOs, prefix constants, envelope helpers, share trim limits, encode methods, and family-specific decode parsing in one file.

#### Target owner / boundary

- Keep protocol runtime entry at the codec layer.
- Split the monolith by packet family into smaller protocol-only codec files.
- `lan_packet_codec.dart` may remain a thin facade/export shell temporarily, but it must stop being the family implementation god-module.

#### Read switch point

- First production read switch:
  - `decodeIncomingPacket(...)`
- Preferred first family extraction:
  - share / thumbnail decode cluster

#### Write switch point

- First production write switch:
  - share / thumbnail encode cluster
  - including `fitShareCatalogEntries(...)`

#### Forbidden writers

- `LanDiscoveryService` as a replacement codec god-module
- `DiscoveryController`
- `DiscoveryPage`
- widgets
- transfer, preview, remote-share, or clipboard owners
- helper facades that centralize multiple codec families again

#### Forbidden dual-write / dual-route paths

- old monolithic family logic plus new family codec logic both active for the same prefix
- duplicated DTO types acting as parallel truth
- copied packet prefix maps or envelope helpers drifting from the canonical codec surface
- split where `LanDiscoveryService` starts owning family-specific wire semantics

### Parity Risks Locked By PR1

- legacy two-part discovery compatibility
- discovery fallback when the third payload segment is not base64url JSON
- base64url JSON envelope rejection for malformed payloads
- share catalog trim limits
- reject-empty decode semantics for transfer items and thumbnail bytes

### Files PR2 Will Need

Must-change:

- `lib/features/discovery/data/lan_packet_codec.dart`
- family codec files under `lib/features/discovery/data/`
- `test/lan_packet_codec_test.dart`
- `test/lan_discovery_service_contract_test.dart`

Likely-change:

- `lib/features/discovery/data/lan_discovery_service.dart`
- protocol handler files that currently import packet types from the monolith
- app-layer consumers that import codec DTOs directly
- `test/lan_discovery_service_packet_codec_test.dart`
- `test/lan_discovery_service_protocol_handlers_test.dart`
- `test/lan_discovery_service_transport_adapter_test.dart`
