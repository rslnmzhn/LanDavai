# Refactor Master Plan (Post-Refactor Baseline)

## 1. Purpose

Этот документ фиксирует post-refactor baseline. Его задача не планировать новые
ownership splits, а закрепить то, что уже является архитектурной нормой, и
обозначить текущие guardrails.

Scope:

- `lib/`
- `test/`
- `docs/`

Out of scope:

- platform folders outside Dart surface
- protocol or storage semantics changes без прямого evidence
- повторное открытие уже закрытых seams

## 2. Current Baseline

Canonical owners и boundaries:

- `DiscoveryReadModel` owns discovery read projection
- `LocalPeerIdentityStore` owns local peer identity persistence/creation
- `SharedCacheCatalog` owns shared-cache metadata truth
- `SharedCacheIndexStore` owns shared-cache index truth
- `SharedCacheMaintenanceBoundary` owns shared-cache recache/remove/progress
- `RemoteShareBrowser` owns remote share browse/session truth
- `RemoteShareMediaProjectionBoundary` owns remote-share thumbnail/media projection
- `FilesFeatureStateOwner` owns explorer/navigation/view state
- `PreviewCacheOwner` owns preview lifecycle/cache truth
- `TransferSessionCoordinator` owns live transfer/session truth
- `VideoLinkSessionBoundary` owns video-link session commands + projection
- `DownloadHistoryBoundary` owns download history truth
- `ClipboardHistoryStore` owns local clipboard history truth
- `RemoteClipboardProjectionStore` owns remote clipboard projection truth

Thin infra ports:

- `SharedCacheRecordStore`
- `SharedCacheThumbnailStore`

These are foundation, not new migration targets.
New work must not silently move their truth back into:

- `DiscoveryController`
- `DiscoveryPage`
- widgets
- repositories
- helper facades or callback bundles

## 3. Guardrails (Current Baseline)

The baseline is enforced by:

- `test/architecture_guard_test.dart` (GATE-07)
- `test/smoke_test.dart` + `test/blocked_entry_flow_regression_test.dart`

Forbidden regressions:

- `SharedCacheCatalogBridge` reintroduction
- discovery/files callback bundle reintroduction
- `part / part of` under `lib/`
- controller ownership of local peer id, video-link session, or thumbnail IO
- broadening of `SharedFolderCacheRepository`
- re-expansion of `LanPacketCodec` or `lan_packet_codec_common.dart`

## 4. What Remains Risky

Workpack 10 remains open because a small set of weak entry flows still lacks
behavior-level UI coverage. See `docs/refactor_workpacks/10_architecture_guard_and_regression_hardening.md`.

Remaining weak-flow gaps:

- discovery -> files launch
- files/viewer entry survivability
- remote-share preview/viewer launch
- history populated/open-folder action survivability

## 5. Completion Standard (Baseline)

This refactor baseline is considered stable when:

- architecture guard tests fail fast on prohibited residue
- explicit UI regression proof covers the remaining weak entry flows above
- `flutter analyze` and `flutter test` stay green
