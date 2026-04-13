# Whole-Share Cache Issue: Current Hashing Model

This file separates the current roles of hashes in the whole-share pipeline.

## Indexed hash truth

`SharedFolderIndexStore` persists optional `sha256` per indexed entry in
`SharedFolderIndexEntry.sha256`.

Current rules:

- owner indexing does not compute `sha256` by default
- refresh keeps the cached `sha256` only when file size and mtime still match
- `persistCachedManifestEntries(...)` updates persisted hashes after sender-side
  preparation has computed them

This means the index may contain:

- no hash yet
- a reusable hash
- a stale hash that is invalidated by size/mtime change

## Fingerprint truth

`SharedCacheIndexStore` also computes:

- folder/tree fingerprints
- scoped-selection fingerprints

Those fingerprints are reuse gates only. They are not per-file transport
integrity truth.

## Sender pre-send hash stage

For whole-share direct-start, `_approveIncomingSharedDownloadRequest(...)`
calls `_buildTransferFilesForCache(... includeHashes: true)`.

That makes sender pre-send hashing mandatory today unless the persisted index
already contains reusable hashes for the scoped selection.

Current behavior inside `_buildTransferFilesForCache(...)`:

- if cached `sha256` is present and size/mtime match, reuse it
- otherwise compute `sha256` before send
- persist refreshed manifest entries back into the index

Successful log evidence (`requestId` `4a32a3ba...`):

- `reusedCachedHashCount = 0`
- `recomputedHashCount = 1005`

That request reached the send path only after all `1005` file hashes had been
computed.

## Sender stream-time hash verification

`FileTransferService.sendFiles(...)` recomputes a streaming digest for each file
while sending it.

Current rule:

- if `TransferSourceFile.sha256` is non-empty, the sender compares the
  streaming digest to that expected hash and fails on mismatch
- if the expected hash is empty, the sender does not fail on sender-side hash
  mismatch for that file

Whole-share direct-start currently does not use the empty-hash fast path. That
fast path only exists for narrow single-file cases.

## Receiver-side verification

The receiver uses two layers:

- manifest verification in `_receiveFiles(...)` if it already has expected
  items
- per-file streaming digest verification while bytes arrive

Separately, legacy requester-side existing-file skip checks in
`_filterMissingIncomingItems(...)` also hash local files when the manifest item
contains a non-empty expected hash.

## What is mandatory before first byte today

For whole-share direct-start:

- scoped selection resolution is mandatory
- live source-file resolution and stat are mandatory
- filling missing or stale sender-side hashes is mandatory today
- transfer header construction is mandatory

What is not mandatory before first byte:

- sender stream-time hash verification itself
- receiver stream-time hash verification itself
- requester post-receive history persistence

## Conclusion

The current whole-share path uses hashes in three distinct roles:

- persisted optional cache/index metadata
- sender pre-send manifest fill
- stream-time verification during transfer

The pre-send hash stage is the part currently sitting on the critical path to
the first byte.
