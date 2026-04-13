# Whole-Share Cache Issue: Blocking Stages Before First Byte

This file isolates what currently blocks a large whole-share send before the
requester receives the first TCP byte.

## Blocking stages

| Stage | Blocking before first byte | Evidence |
| --- | --- | --- |
| Requester receiver startup | Yes, but short | Code: `requestDownloadFromRemoteFiles(...)` starts the receiver before sending the UDP request |
| Sender approval wait | Yes | Code: `_handleDownloadRequest(...)` creates `IncomingSharedDownloadRequest` and returns without preparing files until explicit approval |
| Scoped selection resolution | Yes | Code: `_approveIncomingSharedDownloadRequest(...)` awaits `_buildWholeShareDirectStartSendPlan(...)`; scoped selection still resolves before batch 1 |
| Live filesystem traversal for batch 1 | Yes | Code: batch 1 is still resolved to real files before connect |
| Full whole-share materialization | No longer current behavior | Code: later files are resolved through `resolveBatch(...)` during the active send |
| Full pre-send sender hash fill | No longer current behavior | Code: whole-share direct-start now uses cached-only pre-send hashes and backfills streamed hashes after success |
| Transfer header build | Yes, but late and short | Code: `FileTransferService.sendFiles(...)`; log shows it happens only after sender prepare completes |
| TCP connect attempt | Final blocking step | Code: `_sendDirectSharedDownload(...)` calls `sendFiles(...)` only after sender preparation |

## Timeline evidence available in the current local log

The current local log does not contain both requester-side and sender-side
events for the same whole-share request ID.

What it does contain:

- requester-only successful whole-share requests:
  - `318adf40...`
  - `0c63ccef...`
- sender-only successful whole-share request:
  - `4a32a3ba...`
- requester-only timeout whole-share request:
  - `77c04139...`

That means the current audit can prove the requester-side waiting window and the
sender-side pre-connect preparation window, but it cannot yet prove a single
same-request end-to-end paired chronology from one local log alone.

## Current blocking shape

The old cold-path bottleneck has been narrowed.

Current code evidence:

- `_approveIncomingSharedDownloadRequest(...)` now awaits
  `_buildWholeShareDirectStartSendPlan(...)` before `_sendDirectSharedDownload(...)`
- `_buildWholeShareDirectStartSendPlan(...)` does:
  - scoped selection resolution
  - full lightweight manifest construction
  - batch-1-only live filesystem traversal
  - cached-hash reuse only, with missing hashes deferred
- later files are resolved in `_prepareWholeShareDirectStartContinuationBatch(...)`
  while the transfer is already active

That means current first-byte blocking is now:

- explicit sender approval
- scoped selection resolution
- batch 1 traversal/materialization
- one manifest header build

not:

- full whole-share hash fill
- full whole-share prepared-set construction

## Timeout interaction

The requester receiver timeout is fixed at `180s` in
`FileTransferService.startReceiver(...)`, and it begins when the requester
opens the receiver, not when the sender finishes preparing.

Requester log evidence from a timeout whole-share request (`requestId`
`77c04139...`):

- `16:02:39.690Z` `receiver_started`
- `16:02:39.691Z` `download_request_sent`
- `16:05:39.690Z` `receiver_timeout`

This proves the full sender approval + preparation + connect window must fit
inside the same `180s` receiver lifetime.

## Composite chronology from the current evidence

Current successful requester-side chronology (`requestId` `0c63ccef...`):

- `15:30:55.236Z` requester `download_request_sent`
- `15:31:03.868Z` requester `receiver_connected`

Current successful sender-side chronology (`requestId` `4a32a3ba...`):

- `15:33:21.376Z` sender `sender_whole_share_prepare_start`
- `15:33:21.393Z` sender `sender_whole_share_hash_stage_start`
- `15:33:25.321Z` sender `sender_whole_share_hash_stage_complete`
- `15:33:25.413Z` sender `sender_whole_share_prepare_complete`
- `15:33:25.472Z` sender `send_start`

Current timeout requester-side chronology (`requestId` `77c04139...`):

- `16:02:39.691Z` requester `download_request_sent`
- `16:05:39.690Z` requester `receiver_timeout`

Current timeout sender-side chronology:

- absent in the current local log for `77c04139...`
- this absence is a real evidence gap, not a place to infer silently

## Practical conclusion

The remaining whole-share problem is no longer the original full pre-send
barrier. The current architecture still has a real batch-1 pre-connect window,
but the historical full-set materialization and full-folder hash-fill bottleneck
is no longer the active baseline.
