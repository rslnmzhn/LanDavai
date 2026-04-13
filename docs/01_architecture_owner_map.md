# Architecture Owner Map

This file reflects the current owner boundaries in `lib/`. It is aligned with [AGENTS.md](/e:/Projects/Landa/AGENTS.md) and the existing codebase.

## Core rule

Truth stays in explicit owners and boundaries. `DiscoveryController` is a thin shell for commands, protocol wiring, and discovery-scope orchestration. Widgets and pages stay presentation-only.

## Current owners

- `DiscoveryController`
  Thin shell for discovery commands, protocol entry wiring, friend flows, settings commands, and restart orchestration.
- `DiscoveryReadModel`
  Discovery-facing read projection over controller and supporting stores.
- `DiscoveryNetworkScopeStore`
  Session-scoped local network ranges, active scope selection, grouped local IP sets.
- `NearbyTransferSessionStore`
  Nearby-transfer session truth, active mode/peer/handshake/progress, session-local candidate state.
- `LocalPeerIdentityStore`
  Local peer identity persistence and generation.
- `SharedCacheCatalog`
  Shared-cache metadata truth for owner and receiver caches.
- `SharedCacheIndexStore`
  Shared-cache index truth, persisted compact entry metadata, folder/tree fingerprints, and scoped selection fingerprints used as safe reuse signals.
- `SharedCacheMaintenanceBoundary`
  Shared-cache recache/remove/progress boundary.
- `RemoteShareBrowser`
  Remote share browse session truth, aggregated/per-owner projections, stable token resolution for preview/download.
- `RemoteShareMediaProjectionBoundary`
  Remote-share thumbnail/media projection and sync boundary.
- `FilesFeatureStateOwner`
  Explorer navigation, search, sort, view mode, visible entries.
- `PreviewCacheOwner`
  Preview cache lifecycle, preview artifact directories, cleanup policy.
- `TransferSessionCoordinator`
  Live transfer/session truth, sender-side incoming shared-download approval/reject state, shared-download handshake/progress/preparation states, and ephemeral consumption of fingerprint-backed indexed reuse. It does not own index or fingerprint truth.
- `VideoLinkSessionBoundary`
  Video-link session commands and projection.
- `DownloadHistoryBoundary`
  Persisted download history truth.
- `ClipboardHistoryStore`
  Local clipboard history truth.
- `RemoteClipboardProjectionStore`
  Remote clipboard projection/loading truth.

## Thin infra ports

- `SharedCacheRecordStore`
- `SharedCacheThumbnailStore`

## Guardrails

- Do not move extracted truth back into `DiscoveryController`, `DiscoveryPage`, widgets, repositories, or helper facades.
- Nearby transfer stays separate from LAN discovery and transfer-session ownership.
- `LanPacketCodec` stays a thin facade; family logic remains in dedicated codec files.
- `part / part of` is forbidden under `lib/`.

## Main composition entrypoints

- `lib/app/discovery/discovery_composition.dart`
- `lib/features/discovery/application/discovery_controller.dart`
- `lib/features/discovery/application/discovery_read_model.dart`

## Practical reading order in code

1. `lib/app/discovery/discovery_composition.dart`
2. `lib/features/discovery/application/discovery_controller.dart`
3. The specific owner/boundary for the feature seam you are changing
4. The matching presentation file in `lib/features/*/presentation/`
