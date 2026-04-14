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
5. The requester now has an open `TransferReceiveSession`, but whole-share
   direct-start defers arming the timeout until the sender reports
   `ready_to_connect`.
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
10. `_approveIncomingSharedDownloadRequest(...)` resolves the owner cache and
    calls `_buildWholeShareDirectStartSendPlan(...)`.
11. `_buildWholeShareDirectStartSendPlan(...)` is the staged sender prepare
    entry:
    - reads the whole-root scoped selection through
      `SharedCacheIndexStore.readScopedSelection(...)`
    - builds the full lightweight manifest from indexed entries
    - prepares only batch 1 as real `TransferSourceFile`s
    - reuses cached hashes when size and mtime still match
    - defers missing hashes instead of blocking connect/send
12. Sender emits `ready_to_connect`, requester arms the receiver timeout, and
    `_sendDirectSharedDownload(...)` calls `FileTransferService.sendFiles(...)`.
13. `FileTransferService.sendFiles(...)` now:
    - opens the TCP connection
    - sends the full manifest header once
    - streams batch 1 immediately
    - requests later batches through `resolveBatch(...)`
    - computes stream-time hashes while sending
14. After a successful whole-share send, `TransferSessionCoordinator` hands the
    streamed file hashes back into
    `SharedCacheIndexStore.persistCachedManifestEntries(...)`.
15. The requester logs `receiver_connected` after sender prepare batch 1 and
    connect, not after full whole-share materialization.

## What this means today

- The path is not the old monolithic prepare-everything-then-connect pipeline.
- The current architecture is best described as:
  requester-side deferred-timeout receiver + sender-side first-batch
  prepare-then-connect + in-transfer batch continuation.
- Remaining cold-path cost is now batch-1 preparation and manifest construction,
  not full whole-share hash fill or full prepared-set materialization.
