# Anti-pattern summary — 2026-05-11 — #1

## Scan results
god_class:           critical 1, high 0, medium 0
dual_truth:          1
forbidden_ownership: clean
part_directive:      clean
coupling:            clean

## Priority queue
Ordered by: critical first, then high, then medium.
Max 10 items. One line each.

| # | file | anti_pattern | severity | suggested_boundary |
|---|------|--------------|----------|--------------------|
| 1 | lib/features/transfer/application/transfer_session_coordinator.dart | god_class | critical | Extract remote-share access, preview coordination, cache preparation, send/receive lifecycle, and persistence/history seams from TransferSessionCoordinator |
| 2 | lib/features/transfer/application/transfer_session_coordinator.dart | dual_truth | high | Consolidate incoming request queue ownership between TransferSessionCoordinator and SharedDownloadBoundary |

## Action plan
Max 15 lines. Each item is one concrete PR task, ordered by execution sequence.
Respect depends_on — if task B requires task A, list A first.

1. Extract IncomingTransferRequestBoundary from lib/features/transfer/application/transfer_session_coordinator.dart [depends_on: none]
2. Move shared-download incoming request queue ownership out of duplicate ChangeNotifier state [depends_on: task 1]
3. Extract RemoteShareAccessSessionBoundary from lib/features/transfer/application/transfer_session_coordinator.dart [depends_on: task 1]
4. Extract RemoteFilePreviewTransferBoundary from lib/features/transfer/application/transfer_session_coordinator.dart [depends_on: task 3]
5. Extract TransferCachePreparationBoundary from lib/features/transfer/application/transfer_session_coordinator.dart [depends_on: task 1]
6. Extract IncomingTransferCompletionBoundary from lib/features/transfer/application/transfer_session_coordinator.dart [depends_on: task 5]
7. Extract OutgoingTransferSendBoundary from lib/features/transfer/application/transfer_session_coordinator.dart [depends_on: task 5]

## Blocked / needs decision
Decide whether TransferSessionCoordinator or SharedDownloadBoundary is the canonical owner for incoming transfer request queues.

## Notes
Scan was limited to lib/features/transfer/application/transfer_session_coordinator.dart per request.
