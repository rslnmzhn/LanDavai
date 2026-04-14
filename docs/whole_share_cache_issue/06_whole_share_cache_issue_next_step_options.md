# Whole-Share Cache Issue: Next-Step Options

This file lists concrete architecture options after the current audit.

## Option 1. Timeout-only mitigation

Change:

- increase the requester receiver timeout
- or move receiver startup later without changing sender preparation

Pros:

- small change surface
- low protocol risk

Cons:

- masks the current sender bottleneck instead of reducing it
- keeps long whole-share cold-start latency
- still couples requester wait lifetime to sender approval and preparation

Assessment:

- acceptable only as a temporary safety valve
- not recommended as the main fix

## Option 2. Keep the staged whole-share direct-start baseline and harden it

Change:

- keep the current canonical selector model
- keep ownership boundaries unchanged
- preserve the current staged model:
  - deferred receiver timeout
  - first-batch whole-share prepare
  - connect/send after batch 1
  - batch continuation for later files
  - bounded sender progress emission
  - post-transfer streamed-hash backfill into `SharedCacheIndexStore`
- focus next work only on the remaining cold-path costs inside that baseline

Pros:

- builds on the current implemented architecture instead of replacing it
- preserves current owner seams and canonical selectors
- keeps repeat-run reuse in the correct index owner

Cons:

- still leaves some cost in:
  - scoped selection resolution
  - batch-1 filesystem traversal
  - full manifest construction

Assessment:

- recommended current direction
- now the implemented baseline, with follow-up hardening work still possible

## Option 3. Deeper whole-share model redesign

Change:

- redesign whole-share transfer around a richer staged or streaming model
- possibly separate manifest negotiation, streaming folder listing, or another
  transport shape

Pros:

- maximum flexibility
- potentially best long-term scaling

Cons:

- larger protocol and architecture surface
- higher regression risk
- not justified until the current blocking seam is addressed directly

Assessment:

- not recommended as the next prompt
- should stay behind a later decision point

## Recommended next implementation direction

Recommend option 2.

Specifically, the next implementation prompt should target:

- the remaining batch-1 cold-path cost in
  `_buildWholeShareDirectStartSendPlan(...)`
- any safe manifest/header pressure reduction that does not reintroduce full
  pre-send blocking
- repeat-run reuse opportunities that still belong in `SharedCacheIndexStore`

The next implementation step should not start from a cache-removal or protocol
replacement assumption. The current evidence is already specific enough to work
inside the existing owner seams.
