# Whole-Share Cache Issue: Open Questions

These points are not fully provable from the current code plus the current local
debug log alone.

## 1. Matching sender-side evidence for the timeout request

The current local log contains requester-side timeout evidence for whole-share
`requestId` `77c04139...`, but it does not contain the matching sender-side
stages for that same request ID.

What is still needed:

- the sender device log for that request ID
- or a paired two-device repro that captures both sides

## 2. Matching requester-side evidence for the successful sender trace

The current local log also does not contain requester-side events for the
successful sender-heavy whole-share trace `requestId` `4a32a3ba...`.

What the current local log can prove:

- requester-side successful direct-start exists
- sender-side successful whole-share prepare-then-connect exists

What it still cannot prove from one request ID:

- a single same-request requester + sender success timeline

## 3. Approval latency vs preparation latency on the failing share

The successful whole-share example shows sender preparation completing in a few
seconds for `1005` files and `166 MB`.

The failing whole-share timeout example proves that the requester waited
`180s`, but the current local log does not prove how much of that window was:

- human approval latency
- sender cache/index reuse miss
- live filesystem traversal
- hash recomputation
- sender device filesystem slowness

## 4. Measured repeat-run speedup after streamed-hash backfill

Current code now backfills streamed hashes into `SharedCacheIndexStore` after a
successful whole-share send.

What is still not proven from the current local log alone:

- a measured same-device production comparison for:
  - first run after cold recache
  - second unchanged run after streamed-hash backfill
- how much repeat-run wall-clock improvement comes specifically from hash reuse
  versus other remaining costs

## 5. Whether receiver timeout should remain receiver-first

Current code starts the receiver before sender approval and preparation. The
audit shows why that amplifies sender cold-start cost, but it does not by
itself decide whether the next fix should:

- delay receiver startup
- keep receiver-first semantics but extend lifetime
- or keep receiver-first semantics and reduce the remaining batch-1 pre-send work
