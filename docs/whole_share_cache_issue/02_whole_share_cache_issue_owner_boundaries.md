# Whole-Share Cache Issue: Owner Boundaries

This file isolates the current ownership seams involved in the large
whole-share issue.

## Current owners in this problem

| Seam | Current ownership | Explicit non-ownership |
| --- | --- | --- |
| `RemoteShareBrowser` | Remote browse projection, owner-scoped share tree, token resolution into canonical selectors | It does not own live transfer state, sender preparation, or on-disk source files |
| `SharedCacheCatalog` | Shared-cache metadata records for owner/receiver caches | It does not own scoped selection or live send preparation |
| `SharedCacheIndexStore` | Persisted compact index entries, optional per-file hashes, folder/tree fingerprints, scoped selection fingerprints | It does not own live transfer sessions or transport timing |
| `TransferSessionCoordinator` | Request batching, sender approval state, receiver startup, sender preparation, live transfer/session truth, ephemeral prepared-scope reuse, post-transfer hash handoff into the index owner | It does not own canonical browse tokens or persisted index truth |
| `FileTransferService` | Receiver socket lifetime, TCP connect, manifest header send/receive, streaming transfer, stream-time hash verification | It does not own cache/index truth or selector resolution |
| `LanDiscoveryService` and packet handlers | UDP request/response transport for share access and download requests | They do not own selection semantics or filesystem materialization |

## Truth layers

| Truth layer | Current source of truth | Where it is consumed |
| --- | --- | --- |
| Indexed truth | `SharedCacheIndexStore` entries plus folder/tree and scoped-selection fingerprints | Sender-side selection resolution, safe reuse gating, and post-transfer streamed-hash backfill persistence |
| Prepared transfer-set truth | `_PreparedTransferFile` / `TransferSourceFile` created for one approved request | `TransferSessionCoordinator` and `FileTransferService.sendFiles(...)` |
| File-level verification truth | Optional persisted entry `sha256`, sender stream-time digest, receiver manifest/hash checks | `_buildTransferFilesForCache(...)`, `sendFiles(...)`, `_receiveFiles(...)`, existing-file skip checks |
| Network/runtime truth | UDP download request/response, direct-start `transferPort`, receiver socket timeout, TCP connect/send | `LanDiscoveryService`, `TransferSessionCoordinator`, `FileTransferService` |

## Boundary conclusion

- Index truth ends at canonical normalized selectors plus persisted entry
  metadata and fingerprints.
- Prepared transfer truth begins when the sender resolves those selectors into
  actual readable files on disk for one specific approved request.
- Successful streamed hashes become persisted truth only after the coordinator
  hands them back into `SharedCacheIndexStore`.
- File-level verification truth is layered on top of that prepared set; it is
  not the same thing as scoped fingerprint truth.
- Network runtime truth begins only once the coordinator has created a receiver
  session or started `sendFiles(...)`.

## Important non-root-cause conclusion

The current whole-share failure does not point to `RemoteShareBrowser`
inventing raw filesystem paths. The request path still crosses the protocol
boundary as canonical:

- `cacheId`
- normalized relative file paths
- normalized folder prefixes
- direct-start `transferPort`

Absolute source paths remain sender-local inside `_resolveCacheFilePath(...)`
and never become protocol truth.
