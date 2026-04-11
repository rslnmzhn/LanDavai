# Shared Access Downloads

This file describes the current shared-access browse, preview, and download flow.

## Browse and projection ownership

- `RemoteShareBrowser`
  Owns remote catalog, owner list, aggregated/per-owner projections, preview/download token resolution.
- `FilesFeatureStateOwner`
  Owns explorer/search/sort/view/path state per active route/filter.
- `SharedCacheCatalog`
  Owns cache metadata records for owner and receiver shared caches.
- `SharedCacheIndexStore`
  Owns compact indexed entries, persisted optional file hashes, folder/tree fingerprints, and scoped selection fingerprints.
- `TransferSessionCoordinator`
  Owns live transfer truth, shared-download preparation state, active transfer progress, preview/download requests, and only consumes fingerprint/index state for safe preparation reuse.

## Shared-access browser entry

- UI entry: `lib/features/discovery/presentation/remote_download_browser_page.dart`
- Controller trigger: `DiscoveryController.loadRemoteShareOptions()`
- Remote browse start: `RemoteShareBrowser.startBrowse(...)`

## Preview flow

1. User taps a file in the remote browser.
2. `RemoteDownloadBrowserPage` resolves the file token through `RemoteShareBrowser`.
3. `TransferSessionCoordinator.requestRemoteFilePreview(...)` sends a preview-mode download request.
4. Sender prepares preview content.
5. Receiver auto-accepts the preview transfer.
6. `PreviewCacheOwner` provides the preview artifact path.
7. `LocalFileViewerPage` opens the preview.

Preview remains separate from normal explicit downloads.

## Download flow

1. User explicitly selects files and/or folders in the remote browser.
2. `RemoteShareBrowser.resolveDownloadToken(...)` resolves each token into:
   - explicit file paths by cache, and/or
   - folder prefixes by cache.
3. `TransferSessionCoordinator.requestDownloadFromRemoteFiles(...)` sends the download request.
4. The coordinator now exposes preparation state before bytes arrive:
   - preparing request
   - checking existing local files
   - starting receiver
   - waiting for remote side
5. Active byte progress starts only after the actual file stream begins.

## Folder download model

- Whole shared-root download uses whole-cache semantics.
- Nested folder download uses prefix-based selection, not giant explicit path expansion.
- Path preservation on receive remains intact for whole-root downloads.

## Fingerprint-backed preparation reuse

The current normal shared-download path uses fingerprint/index reuse in two layers:

- `SharedCacheIndexStore`
  - computes deterministic folder/tree fingerprints from the current indexed state
  - computes deterministic scoped-selection fingerprints for whole-root or filtered prefix/file selections
  - invalidates those fingerprints automatically when the indexed state changes
- `TransferSessionCoordinator`
  - reads the current scoped selection through `readScopedSelection(...)`
  - may reuse an ephemeral prepared transfer file list only when the scoped selection fingerprint is unchanged
  - still rebuilds the real prepared file list when the scoped fingerprint changes or the scoped cache is absent

This means:

- unchanged large whole-root downloads can reuse previously prepared indexed scope inputs
- unchanged nested folder/prefix downloads can do the same
- changed indexed folder state forces rebuild instead of trusting stale prepared scope data

## What still rebuilds

Fingerprint reuse is a fast freshness gate, not file-level truth.

- Preview remains on its own preparation path and does not use the normal prepared-scope reuse cache.
- Real filesystem-backed prepared files are still rebuilt when the scoped fingerprint changes.
- Per-file correctness such as existing-local-file checks and send/receive verification still remain outside folder fingerprint truth.

## Current handshake behavior

Normal shared downloads can take one of two paths:

- Legacy path:
  `DownloadRequest -> TransferRequest -> TransferDecision -> TCP send`
- Direct-start path for explicit file/folder-prefix selections:
  requester starts receiver first, includes `transferPort` in the download request, sender connects directly without the extra transfer request round-trip.

Preview stays on the legacy path.

## Current sender confirmation behavior

There is no sender-side explicit approval UI for shared-access downloads in the current production flow.

- Sender may emit a notification/notice.
- Shared download is prepared automatically on the sender side.

## Main files

- `lib/features/discovery/application/remote_share_browser.dart`
- `lib/features/discovery/presentation/remote_download_browser_page.dart`
- `lib/features/transfer/application/transfer_session_coordinator.dart`
- `lib/features/transfer/data/file_transfer_service.dart`
- `lib/features/discovery/data/lan_discovery_service.dart`
- `lib/features/discovery/data/lan_share_packet_codec.dart`

## Current regression coverage

- `test/shared_cache_index_store_test.dart`
- `test/remote_share_browser_test.dart`
- `test/remote_share_viewer_flow_regression_test.dart`
- `test/transfer_session_coordinator_test.dart`
- `test/lan_discovery_service_protocol_handlers_test.dart`
