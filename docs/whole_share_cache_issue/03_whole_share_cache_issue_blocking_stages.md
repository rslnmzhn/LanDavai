# Whole-Share Cache Issue: Blocking Stages Before First Byte

This file isolates what currently blocks a large whole-share send before the
requester receives the first TCP byte.

## Blocking stages

| Stage | Blocking before first byte | Evidence |
| --- | --- | --- |
| Requester receiver startup | Yes, but short | Code: `requestDownloadFromRemoteFiles(...)` starts the receiver before sending the UDP request |
| Sender approval wait | Yes | Code: `_handleDownloadRequest(...)` creates `IncomingSharedDownloadRequest` and returns without preparing files until explicit approval |
| Scoped selection resolution | Yes | Code: `_approveIncomingSharedDownloadRequest(...)` awaits `_buildTransferFilesForCache(...)`; log stage `sender_whole_share_scoped_selection_resolution_*` appears before connect |
| Live filesystem traversal | Yes | Code: `_buildTransferFilesForCache(...)` stats and resolves each selected file before send |
| Sender hash stage | Yes when hashes are missing or stale | Code: whole-share uses `includeHashes: true`; log stage `sender_whole_share_hash_stage_*` appears before connect |
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

## Cold whole-share direct-start is effectively prepare-then-connect

The current whole-share direct-start path is cold-path blocking when the
prepared-scope cache is absent.

Code evidence:

- `_approveIncomingSharedDownloadRequest(...)` awaits
  `_buildTransferFilesForCache(...)` before `_sendDirectSharedDownload(...)`
- `_buildTransferFilesForCache(...)` does:
  - scoped selection resolution
  - live filesystem traversal
  - optional hash reuse or full recomputation
  - optional manifest persistence back into the index

Log evidence from a successful whole-share request (`requestId`
`4a32a3ba...`):

- `15:33:21.376Z` `sender_whole_share_prepare_start`
- `15:33:21.393Z` `sender_whole_share_live_filesystem_traversal_start`
- `15:33:21.393Z` `sender_whole_share_hash_stage_start`
- `15:33:25.321Z` `sender_whole_share_hash_stage_complete`
- `15:33:25.413Z` `sender_whole_share_prepare_complete`
- `15:33:25.413Z` `sender_whole_share_direct_send_connect_attempt_start`
- `15:33:25.472Z` `transfer_header_built`
- `15:33:25.472Z` `send_start`

That sequence shows a fully blocking sender preparation window before connect.

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

The current large whole-share problem is not just "receiver timed out". The
architecture currently makes the receiver wait through all sender pre-send work,
and that sender work can remain cold and expensive.
