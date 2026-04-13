# Whole-Share Cache Issue: Current Failure Modes

This file lists the currently confirmed failure modes around large whole-share
downloads.

## 1. Requester receiver timeout before sender connects

Status: confirmed by code and requester log

What happens:

- requester starts a receiver with a fixed `180s` timeout
- sender does not connect before that timeout expires
- requester closes the receiver and records `receiver_timeout`

Evidence:

- code: `FileTransferService.startReceiver(...)`
- log: whole-share `requestId` `77c04139...` shows `download_request_sent`
  followed by `receiver_timeout` exactly `180s` later

## 2. Sender-side whole-share preparation bottleneck

Status: confirmed by code, confirmed by successful sender log, inferred as the
dominant timeout candidate

What happens:

- sender approval is explicit
- after approval, sender performs whole-share preparation before connect
- cold whole-share preparation can include full traversal plus full hash fill

Evidence:

- code: `_approveIncomingSharedDownloadRequest(...)` awaits
  `_buildTransferFilesForCache(...)` before `_sendDirectSharedDownload(...)`
- log: successful whole-share `requestId` `4a32a3ba...` shows sender-side
  scoped selection, traversal, hash stage, and only then connect/send

Why it matters:

- this is the strongest current explanation for the long pre-connect window
- it is a better fit than browser/index path corruption, which the current code
  does not support

## 3. Timeout with missing sender-side evidence in the same local log

Status: confirmed as a diagnostic gap, not as a separate runtime bug

What happens:

- the current local timeout example proves that the requester waited `180s`
  without a connection
- the same local log does not contain the matching sender-side stages for that
  exact request ID

Consequence:

- the timeout itself is confirmed
- the exact sender stall stage for that request is still unproven from the
  current single local log alone

## 4. Historical share-access snapshot mismatch

Status: confirmed historically, contrast only

What happened:

- older `share_access_snapshot` sends failed with immediate sender SHA mismatch
- later logs show the same snapshot path completing successfully after atomic
  finalize and preflight checks

Why it matters:

- it is no longer the main explanation for current whole-share timeout behavior
- it is useful as contrast because it shows a different seam with a different
  failure signature: immediate `send_failure`, not slow pre-connect timeout

## 5. Controlled sender prepare failures

Status: confirmed by code, not evidenced in the current large whole-share log

Current controlled failure exits include:

- cache not found
- no prepared files
- generic preparation exception

These return through sender-side rejection or error notice paths. They are not
the same as the slow whole-share timeout case.

## Current ranked interpretation

1. Sender pre-send whole-share preparation is the primary bottleneck candidate.
2. Receiver lifetime starting too early amplifies that bottleneck into timeout.
3. Path or selector corruption is not currently supported by the code audit.
