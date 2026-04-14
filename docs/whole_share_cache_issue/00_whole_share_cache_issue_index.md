# Whole-Share Large-Folder Analysis

This subtree is the current working analysis for large whole-share
shared-download architecture. `docs/00_index.md` remains the only top-level
docs entrypoint; this subtree is a focused branch linked from it.

## Current headline findings

- The original full pre-send hash barrier is no longer the current baseline.
- Whole-share direct-start now uses staged sender preparation:
  first-batch prepare, connect/send, then batch continuation.
- Sender progress is now rate-limited inside the transfer owner instead of
  flooding the UI-facing path.
- Successful whole-share sends now backfill streamed hashes into
  `SharedCacheIndexStore`, so repeat runs can reuse them when size and mtime
  still match.
- Remaining whole-share cost is now dominated by scoped selection resolution,
  batch-local filesystem traversal, and single-header manifest construction,
  not by the historical full pre-send hash fill.

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
