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

## Whole-share pre-send hashing now

Whole-share direct-start no longer requires full pre-send hash fill.

Current behavior inside `_buildWholeShareDirectStartSendPlan(...)`:

- if cached `sha256` is present and size/mtime match, reuse it
- otherwise leave the pre-send hash empty for that file
- send starts with batch 1 even when later files still have no persisted hash

This means the current pre-send role of hashes is:

- reuse known valid hashes when cheap
- do not block connect/send on missing hashes

## Sender stream-time hash verification

`FileTransferService.sendFiles(...)` recomputes a streaming digest for each file
while sending it.

Current rule:

- if `TransferSourceFile.sha256` is non-empty, the sender compares the
  streaming digest to that expected hash and fails on mismatch
- if the expected hash is empty, the sender does not fail on sender-side hash
  mismatch for that file

Whole-share direct-start now also uses optional pre-send hashes:

- known hashes remain explicit and are verified during send
- unknown hashes are still streamed and hashed during send
- sender-side streamed hashes are then backfilled into the shared-cache index
  after a successful send

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
- batch-1 live source-file resolution and stat are mandatory
- filling missing or stale sender-side hashes is not mandatory anymore
- transfer header construction is mandatory

What is not mandatory before first byte:

- sender stream-time hash verification itself
- receiver stream-time hash verification itself
- requester post-receive history persistence

## Conclusion

The current whole-share path uses hashes in three distinct roles:

- persisted optional cache/index metadata
- lightweight pre-send manifest fill from indexed truth
- stream-time verification during transfer
- post-transfer streamed-hash backfill into `SharedCacheIndexStore`

The old full pre-send hash stage is now historical. Current whole-share
critical-path cost sits in selection resolution, batch-1 traversal, and header
construction.
