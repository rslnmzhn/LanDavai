# Whole-Share Cache Issue: Current Pipeline

This file describes the current production whole-share direct-start pipeline for
large shared folders.

## Preconditions

- The requester opens `RemoteDownloadBrowserPage`.
- The current production browser no longer depends on aggregated
  `loadRemoteShareOptions()` as its primary path.
- The requester uses the per-device access flow to sync a share-access snapshot
  first, then browses that owner-scoped projection in `RemoteShareBrowser`.

## Step-by-step flow

1. User selects the root shared folder for one device in
   `remote_download_browser_page.dart`.
2. `RemoteShareBrowser.resolveDownloadToken(...)` resolves that folder token to:
   - `cacheId`
   - empty `selectedRelativePaths`
   - empty `selectedFolderPrefixes`
   - non-empty `sharedLabel`
3. `RemoteDownloadBrowserPage._downloadSelectedFiles()` batches the request by
   owner IP and calls
   `TransferSessionCoordinator.requestDownloadFromRemoteFiles(...)`.
4. `requestDownloadFromRemoteFiles(...)` normalizes selectors, detects
   `requestsWholeShare == true`, resolves receive layout to
   `preserveSharedRoot`, starts the receiver first, and only then sends
   `sendDownloadRequest(...)`.
5. The requester now has an open `TransferReceiveSession` and is already
   counting down the receiver timeout before the sender has approved or prepared
   anything.
6. `LanDiscoveryService.sendDownloadRequest(...)` sends a UDP request carrying:
   - `cacheId`
   - empty `selectedRelativePaths`
   - empty `selectedFolderPrefixes`
   - direct-start `transferPort`
7. On the sender, `LanShareProtocolHandler.handleDownloadRequestPacket(...)`
   maps the packet to `DownloadRequestEvent`, and
   `TransferSessionCoordinator.handleDownloadRequestEvent(...)` forwards it into
   `_handleDownloadRequest(...)`.
8. `_handleDownloadRequest(...)` does not start sending immediately for normal
   shared downloads. It creates `IncomingSharedDownloadRequest`, surfaces sender
   approval UI, and waits for explicit approve/reject.
9. When the sender approves,
   `respondToIncomingSharedDownloadRequest(...)` calls
   `_approveIncomingSharedDownloadRequest(...)`.
10. `_approveIncomingSharedDownloadRequest(...)` resolves the owner cache,
    computes `relativePathFilter == null` and `folderPrefixFilter == null`, and
    calls `_buildTransferFilesForCache(... includeHashes: true)`.
11. `_buildTransferFilesForCache(...)` is the main sender-side preparation
    stage:
    - reads the scoped selection for the whole root through
      `SharedCacheIndexStore.readScopedSelection(...)`
    - checks the ephemeral prepared-scope cache
    - on cache miss, resolves each indexed entry back to a live source file
    - stats each file
    - reuses cached `sha256` only when size and mtime still match
    - otherwise computes fresh `sha256`
    - persists refreshed manifest entries back into the shared-cache index
12. Only after `_buildTransferFilesForCache(...)` completes does the sender
    call `_sendDirectSharedDownload(...)`.
13. `_sendDirectSharedDownload(...)` calls `FileTransferService.sendFiles(...)`,
    which:
    - opens the TCP connection
    - builds and sends the transfer header
    - streams file bytes
    - recomputes sender-side streaming hashes while sending
14. The requester logs `receiver_connected` only after the sender completes the
    whole pre-send preparation and the TCP connection is accepted.
15. If the sender has not connected before the receiver timeout expires,
    `FileTransferService.startReceiver(...)` closes the receiver and the request
    ends in `receiver_timeout` / `receiver_result(success=false)`.

## What this means today

- The path is not a pure monolithic legacy handshake anymore because the
  requester starts the receiver early and the sender connects directly.
- The path is also not a fully staged streaming pipeline because the sender
  still performs most whole-share preparation before `Socket.connect(...)`.
- The current architecture is best described as:
  requester-side receiver-first direct-start + sender-side prepare-then-connect.
