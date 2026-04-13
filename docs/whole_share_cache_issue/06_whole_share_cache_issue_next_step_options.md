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

## Option 2. Stage whole-share direct-start earlier and reduce pre-send hashing

Change:

- keep the current canonical selector model
- keep ownership boundaries unchanged
- make whole-share direct-start less prepare-then-connect by reducing what must
  happen before `send_start`
- narrow candidates include:
  - start TCP connect after selection and file-size materialization, not after
    full hash fill
  - make whole-share sender hashes more lazy or conditional when transport
    correctness allows it
  - preserve persisted index hashes as a reuse accelerator, not as the only
    integrity truth

Pros:

- attacks the current critical path directly
- preserves current owner seams and canonical selectors
- fits the current direct-start model instead of replacing it wholesale

Cons:

- requires careful treatment of:
  - receiver-side existing-file skip behavior
  - manifest completeness
  - sender/receiver verification semantics

Assessment:

- recommended current direction
- best match for the evidence in code and logs

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

- the sender-side whole-share pre-send window in
  `_approveIncomingSharedDownloadRequest(...)` and
  `_buildTransferFilesForCache(...)`
- the receiver lifetime coupling caused by starting the receiver before sender
  approval and cold preparation finish

The next implementation step should not start from a cache-removal or protocol
replacement assumption. The current evidence is already specific enough to work
inside the existing owner seams.
