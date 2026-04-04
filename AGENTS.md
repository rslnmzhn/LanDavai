# AGENTS.md

## Purpose
Single source of truth for implementation and design decisions across chats/agents.
Goal: keep Landa behavior, visuals, and data model consistent.

## Product
- App name: Landa
- Type: peer-to-peer LAN file transfer (no central transfer server for file payloads)
- Platforms: Windows, Linux, Android, iOS
- Promise: fast local transfer, explicit trust, predictable UX

## Core Stack
- Framework: Flutter (stable)
- Language: Dart
- UI state (current baseline): `ChangeNotifier` controllers, owners, and stores
- Navigation (when introduced): `go_router`
- Persistence:
  - `sqflite` (mobile)
  - `sqflite_common_ffi` (Windows/Linux)
  - `path_provider` for app storage paths
- Hashing for stable cache IDs: `crypto` (`sha256`)
- Lints: `flutter_lints`, no new analyzer warnings in touched files

## Architecture Baseline (Post-Refactor)
Canonical state ownership is now split across explicit owner boundaries.

Current owner/boundary map:
- `DiscoveryController`: discovery shell state, device actions, friend flows, settings commands, protocol entry wiring, and discovery-scope restart orchestration only
- `DiscoveryReadModel`: consumer-facing read projection over discovery shell plus supporting stores
- `DiscoveryNetworkScopeStore`: session-scoped local network range truth, active discovery scope selection, and grouped local IP sets
- `NearbyTransferSessionStore`: nearby-transfer session truth, active mode, peer, handshake, transfer progress, and session-local candidate state
- `LocalPeerIdentityStore`: local peer identity persistence and generation
- `SharedCacheCatalog`: shared-cache metadata truth
- `SharedCacheIndexStore`: shared-cache index truth
- `SharedCacheMaintenanceBoundary`: shared-cache recache/remove/progress boundary
- `RemoteShareBrowser`: remote share browse session truth
- `RemoteShareMediaProjectionBoundary`: remote-share thumbnail/media projection boundary
- `FilesFeatureStateOwner`: explorer/navigation/filter/sort/view state
- `PreviewCacheOwner`: preview cache truth, preview artifact lifecycle, and preview cleanup policy
- `TransferSessionCoordinator`: live transfer/session truth
- `VideoLinkSessionBoundary`: video-link session command and projection boundary
- `DownloadHistoryBoundary`: persisted download history truth
- `ClipboardHistoryStore`: local clipboard history truth
- `RemoteClipboardProjectionStore`: remote clipboard projection/loading truth
- Infra ports (thin collaborators):
  - `SharedCacheRecordStore`
  - `SharedCacheThumbnailStore`

Rules:
- Do not move any extracted truth back into `DiscoveryController`, `DiscoveryPage`,
  widgets, repositories, or new facades/helpers.
- `DiscoveryController` may stay a thin command/protocol shell where public entry
  still needs it, but it must not regain canonical ownership for extracted seams.
- Raw interface enumeration belongs in discovery data catalogs, subnet grouping
  belongs in application, and visible network labels belong in presentation.
- `DiscoveryController` must not compute subnet groups or adapter label
  heuristics. It may only consume already-computed active scope IP sets and
  orchestrate restart/refresh.
- `DiscoveryReadModel` network-scope filtering is projection-only and must
  derive from the same grouped subnet identity used by
  `DiscoveryNetworkScopeStore`.
- Nearby-transfer flow is a separate feature seam. Do not route new nearby
  transfer behavior through `DiscoveryController`,
  `TransferSessionCoordinator`, or the existing LAN transfer protocol.
- `NearbyTransferSessionStore` must remain a session owner only; it must not
  absorb QR codec logic, socket transport implementation, picker logic, or
  storage collision policy.
- Nearby-transfer candidate devices must come from an honest narrow projection
  over existing visible peers or transport-local candidates for the active
  session. Do not create a second canonical LAN discovery truth.
- `VideoLinkShareService.activeSession` remains a separate seam from
  `TransferSessionCoordinator`; do not silently merge those seams.
- `SharedCacheCatalogBridge` is deleted and forbidden by guard tests.
- The discovery/files callback bundle is deleted and forbidden by guard tests.
- `part / part of` is forbidden under `lib/` and enforced by guard tests.
- Protocol family logic must remain in dedicated codec files; `LanPacketCodec`
  stays a thin facade, and `lan_packet_codec_common.dart` must stay common-only.

## Source Layout Contract
Use this structure unless there is a strong architectural reason to deviate:

```text
lib/
  app/
    app.dart
    router.dart
    discovery/
      discovery_composition.dart
    theme/
      app_theme.dart
      app_colors.dart
      app_spacing.dart
      app_radius.dart
      app_typography.dart
  core/
    errors/
    storage/
    utils/
    widgets/
  features/
    clipboard/
      application/
      data/
      domain/
      presentation/
    discovery/
      application/
        discovery_network_scope.dart
        discovery_network_scope_grouper.dart
        discovery_network_scope_store.dart
      data/
        discovery_network_interface_catalog.dart
      domain/
      presentation/
        discovery_network_scope_selector.dart
    files/
      application/
      presentation/
    history/
      application/
      data/
      domain/
    nearby_transfer/
      application/
      data/
      presentation/
    settings/
      application/
      data/
      domain/
      presentation/
    transfer/
      application/
      data/
      domain/
test/
  architecture_guard_test.dart
  smoke_test.dart
  blocked_entry_flow_regression_test.dart
  discovery_controller_network_scope_test.dart
  discovery_network_scope_store_test.dart
  *_flow_regression_test.dart
  *_owner_test.dart
  *_boundary_test.dart
  *_store_test.dart
```

Rules:
- No UI code in data repositories.
- No direct networking calls from widgets.
- `UdpDiscoveryTransportAdapter` and `NetworkHostScanner` must consume the
  provided active `localSourceIps` set; do not reintroduce local interface
  enumeration there.
- Shared design tokens only in `lib/app/theme/*`.

## Visual Identity Contract (Do Not Drift)
Tone: calm, modern, soft-technical, trustworthy.

### Color Tokens (Single Source of Truth)
- `brandPrimary`: `#8B7CF6`
- `brandPrimaryDark`: `#6D5CE7`
- `brandAccent`: `#C4B5FD`
- `bgBase`: `#F6F5FF`
- `surface`: `#FFFFFF`
- `surfaceSoft`: `#F1F0FF`
- `textPrimary`: `#1F1F2E`
- `textSecondary`: `#5B5B73`
- `textMuted`: `#8C8CA1`
- `success`: `#4CAF93`
- `warning`: `#D4A373`
- `error`: `#C06C84`

Rules:
- No one-off hex colors in widgets.
- Use only tokens from `app_colors.dart`.

### Typography
- Primary: Manrope
- Mono/numeric: JetBrains Mono
- Prefer semantic text styles from theme; avoid ad-hoc `TextStyle`.

### Spacing / Shape
- Spacing: `4, 8, 12, 16, 20, 24, 32`
- Radius: `8, 12, 16, 24`
- Default card radius: `16`
- Button height: `44` mobile, `40` desktop

## UX Contract
Transfer-related flows must expose states:
- `idle`
- `discovering`
- `pairing`
- `transferring`
- `paused`
- `completed`
- `failed`

Rules:
- Critical actions require explicit confirmation.
- Errors must be actionable and human-readable.
- Empty states must contain a next step.

## Networking Contract (Current Implementation Baseline)
- App presence discovery: UDP broadcast handshake in LAN.
- Handshake payload identifiers: `LANDA_DISCOVER_V1` / `LANDA_HERE_V1`.
- Packets include per-instance ID to avoid self-detection loops.
- Discovery scope is driven by explicit active `localSourceIps`.
- `DiscoveryNetworkScopeStore` owns grouped local ranges and the selected
  `Все` / per-range scope.
- `Все` maps to the union of all eligible grouped ranges.
- Discovery input is filtered to the selected active scope; read-model filtering
  is projection-only over the same grouped subnet identity.
- LAN host visibility uses ARP/neighbor table first.
- TCP probing is fallback-only and disabled by default.
- Keep manual IP connect as fallback path for edge networks.
- Nearby transfer v1 is separate from LAN discovery and existing transfer
  session ownership.
- `lan_fallback` nearby transport owns direct-socket session transport only.
  It may reuse visible-peer projection input through a narrow adapter, but it
  must not create a second discovery protocol.
- `lan_fallback` QR payloads must carry the direct-socket connect info needed
  by the receiver: `host/ip`, `port`, and `sessionId`.

## Device Identity Contract
- IP is transient; MAC is identity key when available.
- User device alias is bound to normalized MAC (`aa:bb:cc:dd:ee:ff`).
- If IP changes but MAC is the same, alias must remain.

## Persistence Contract (SQLite)
Database file:
- `<app_support>/Landa/landa.sqlite`

Tables:
1. `known_devices`
   - `mac_address` (PK)
   - `alias_name`
   - `last_known_ip`
   - `last_seen_at`
   - `updated_at`
2. `shared_folder_caches`
   - `cache_id` (PK)
   - `role` (`owner` / `receiver`)
   - `owner_mac_address`
   - `peer_mac_address` (nullable)
   - `root_path`
   - `display_name`
   - `index_file_path`
   - `item_count`
   - `total_bytes`
   - `updated_at`

Rules:
- MAC values must be normalized before write/read.
- Use transactions for multi-row updates.
- Never hardcode absolute user paths in code.

## Shared Folder Cache Contract
Directory:
- `<app_support>/Landa/shared_folder_caches/`

Format:
- Lightweight JSON index with compact entry fields (`p`, `s`, `m`).
- Store on both sides:
  - owner device
  - receiver device

Naming:
- File name format: `<role>_<sanitized_display_name>_<cache_id>.landa-cache.json`
- `cache_id` is deterministic hash of:
  - schema version
  - role
  - owner MAC
  - peer MAC (or `-`)
  - normalized root identity/path

Goals:
- Stable identity across sessions
- Low collision risk
- Human-readable enough for debugging

## Code Quality Contract
- Keep files focused; split widgets over ~200 lines.
- Prefer pure functions for parsing/mapping/indexing.
- Add tests for storage logic and protocol framing when touched.
- Add dependencies only with direct product need.
- Preserve backward compatibility for persisted data when feasible.
- Prefer direct owner-backed contracts over compatibility shells when the owner
  already exists.
- Do not normalize temporary migration residue into new code.

## Agent Response Contract
When implementing changes:
1. State assumptions briefly.
2. Implement code, not only proposals.
3. Report exact files changed.
4. Include verification (`analyze`, `test`, manual checks run).
5. List remaining risks / TODOs.

## Prompt Template
Use this structure in future requests:

```text
Task:
Context:
Constraints:
Target platforms:
Definition of done:
Out of scope:
```

Optional lock:
`Follow AGENTS.md visual identity and do not introduce new design tokens.`

## Definition of Done (Default)
- Builds on touched platforms.
- No new analyzer warnings in touched files.
- Theme/token contract respected.
- UX states handled for loading/success/error.
- Changes summarized with file list and verification notes.
- If Windows `flutter test` needs the stale
  `build/native_assets/windows/sqlite3.dll` rename workaround, call it out
  explicitly as an environment issue, not as an app architecture defect.

## Anti-drift Guarantees

The following must not regress:

- No return of `SharedCacheCatalogBridge`
- No callback-based discovery/files coupling
- No `part / part of` under `lib/`
- No controller ownership of:
  - local peer identity
  - network scope grouping / adapter label heuristics
  - video-link sessions
  - thumbnail IO
- No reintroduction of local interface enumeration inside:
  - `DiscoveryController`
  - `UdpDiscoveryTransportAdapter`
  - `NetworkHostScanner`
- No broadening of:
  - `SharedFolderCacheRepository`
  - `LanPacketCodec`
  - `lan_packet_codec_common.dart`
- No reintroduction of local peer identity inside `FriendRepository`
