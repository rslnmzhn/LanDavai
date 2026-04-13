# Whole-Share Large-Folder Analysis

This subtree is the current working analysis for large whole-share
shared-download failures. `docs/00_index.md` remains the only top-level docs
entrypoint; this subtree is a focused branch linked from it.

## Current headline findings

- The current whole-share direct-start path is hybrid, not fully staged:
  requester-side receiver startup happens early, but sender-side whole-share
  preparation remains prepare-then-connect.
- The dominant cold-path blocking work is sender-side
  `_buildTransferFilesForCache(... includeHashes: true)`, which can perform
  full scoped selection resolution, live filesystem traversal, and hash fill
  before the first TCP byte.
- The requester receiver timeout starts before sender approval and preparation,
  so approval + sender preparation + connect must all fit inside the same
  `180s` window.
- Current code and logs point to a combination of sender pre-send preparation
  cost and receiver lifetime mismatch, not to browser token corruption or raw
  path leakage across the protocol boundary.

## Reading order

1. [01_whole_share_cache_issue_current_pipeline.md](/e:/Projects/Landa/docs/whole_share_cache_issue/01_whole_share_cache_issue_current_pipeline.md)
2. [02_whole_share_cache_issue_owner_boundaries.md](/e:/Projects/Landa/docs/whole_share_cache_issue/02_whole_share_cache_issue_owner_boundaries.md)
3. [03_whole_share_cache_issue_blocking_stages.md](/e:/Projects/Landa/docs/whole_share_cache_issue/03_whole_share_cache_issue_blocking_stages.md)
4. [04_whole_share_cache_issue_hashing_model.md](/e:/Projects/Landa/docs/whole_share_cache_issue/04_whole_share_cache_issue_hashing_model.md)
5. [05_whole_share_cache_issue_failure_modes.md](/e:/Projects/Landa/docs/whole_share_cache_issue/05_whole_share_cache_issue_failure_modes.md)
6. [06_whole_share_cache_issue_next_step_options.md](/e:/Projects/Landa/docs/whole_share_cache_issue/06_whole_share_cache_issue_next_step_options.md)
7. [90_whole_share_cache_issue_open_questions.md](/e:/Projects/Landa/docs/whole_share_cache_issue/90_whole_share_cache_issue_open_questions.md)

## Evidence base

- Current code in the browser, transfer, cache/index, and protocol seams
- The existing local debug log under `<app_support>/Landa/logs/debug.log`
