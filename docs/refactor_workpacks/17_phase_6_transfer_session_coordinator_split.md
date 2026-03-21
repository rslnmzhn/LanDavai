# Workpack: Phase 6 Transfer Session Coordinator Split

## 1. Scope

- Вынести transfer negotiation and runtime transfer session ownership в `TransferSessionCoordinator`.
- Разорвать split session control between controller, protocol handlers, and transfer execution services.
- Не входит: `VideoLinkShareService.activeSession`; это secondary subsystem per master plan and explicitly out of scope here.

## 2. Source linkage

- `Master phase`: Phase 6
- `Depends on`: `06`, `21`
- `Unblocks`: `13b`, `23`, `18`
- `Related workpacks`: `07`, `08`, `09`

## 3. Problem slice

Master plan фиксирует, что transfer negotiation and runtime session state fragmented across protocol callbacks and transfer execution glue. Этот slice выделен отдельно, потому что live transfer session owner должен быть один до удаления implicit callback mesh.

## 4. Legacy owner and target owner

- `Legacy owner`: `DiscoveryController` plus protocol and service glue
- `Target owner`: `TransferSessionCoordinator`
- `State seam closed`: transfer session orchestration separate from transport, persistence, and file execution
- `Single write authority after cutover`: `TransferSessionCoordinator`
- `Forbidden writers`: `DiscoveryController`, `LanDiscoveryService`, protocol handlers after event publication, `FileTransferService`, widgets, `VideoLinkShareService` for the transfer-session seam
- `Forbidden dual-write paths`: coordinator session mutation in parallel with controller, protocol, or service-owned session mutation

## 5. Source of truth impact

- что сейчас является truth:
  - mixed controller callbacks, protocol sends, and transfer service state transitions
- что станет truth:
  - `TransferSessionCoordinator`
- что станет projection:
  - transfer progress/status cards and history read-models only
- что станет cache:
  - `transfer_history` remains durable audit/history storage, not live session truth
- что станет temporary bridge only:
  - `TransferSessionBridge`

## 6. Read/write cutover

- `Legacy read path`: UI and services consult mixed controller and service state
- `Target read path`: UI and related services consult coordinator session model
- `Read switch point`: no active transfer view or execution decision depends on controller-owned runtime state
- `Legacy write path`: request, decision, progress, and finalize steps mutate session state through multiple actors
- `Target write path`: session lifecycle transitions go through coordinator only
- `Write switch point`: accept, reject, start, finalize, and progress updates stop mutating mixed session state
- `Dual-read allowed?`: yes, for session continuity regression only
- `Dual-write allowed?`: no

## 7. Temporary bridge

- `Bridge name`: `TransferSessionBridge`
- `Why it exists`: preserve live transfer flows while transfer session authority is consolidated
- `Phase introduced`: Phase 6
- `Max allowed lifetime`: through Phase 6 only
- `Deletion phase`: this workpack
- `Forbidden long-term use`: cannot leave session ownership split between coordinator and legacy actors

## 8. Concrete migration steps

1. inventory transfer session lifecycle transitions across controller, protocol, and transfer execution glue
2. exclude `VideoLinkShareService.activeSession` explicitly from this workpack scope
3. route transfer session creation, decision, progress, and finalization through coordinator
4. switch transfer UI and service consumers to coordinator projection
5. keep transport and file execution behind command/result boundaries only
6. run `GATE-02`, `GATE-04`, and `GATE-07`
7. delete `TransferSessionBridge` after end-to-end proof

## 9. Evidence and source anchors

- `Evidence level`: Strong inference from code structure
- `Source of truth`:
  - `docs/refactor_master_plan.md`
  - `lib/features/discovery/application/discovery_controller.dart` / `_onTransferRequest`, `_onTransferDecision`, `_downloadHistory`
  - `lib/features/discovery/data/lan_discovery_service.dart` / `LANDA_TRANSFER_REQUEST_V1`, `LANDA_TRANSFER_DECISION_V1`, `sendTransferRequest`, `sendTransferDecision`
  - `lib/features/transfer/data/file_transfer_service.dart` / `FileTransferService`, `startReceiver`, `sendFiles`
  - `lib/features/transfer/data/video_link_share_service.dart` / `VideoLinkShareService`, `activeSession`
- `Compatibility anchors`:
  - `transfer_history`
  - UDP packet envelope semantics for transfer packet families
  - handshake identifiers visible from Dart around transfer negotiation
- `Missing artifact`:
  - current Dart-layer audit does not prove that `VideoLinkShareService.activeSession` belongs to the same runtime session seam as file transfer negotiation
- `Impact of uncertainty`:
  - blindly merging video-link publication session into the coordinator would widen scope and create a new mega-owner
- `Safest interim assumption`:
  - keep `VideoLinkShareService.activeSession` explicitly out of scope for this workpack and revisit it only as secondary decomposition after primary transfer-session cutover

## 10. Test gate

- `До начала нужны`: `GATE-02`, `GATE-04`, `GATE-07`
- `Подтверждают cutover`: inbound and outbound transfer sessions complete under coordinator-owned runtime state
- `Hard stop failure`: any active transfer still depends on controller-owned or service-owned session truth after cutover

## 11. Completion criteria

- `TransferSessionCoordinator` is the only transfer-session writer
- transport handlers and execution services no longer own transfer session truth
- `TransferSessionBridge` is deleted
- `VideoLinkShareService.activeSession` remains explicitly excluded from this scope

## 12. Deletions unlocked

- implicit controller and protocol transfer-session ownership paths
- `TransferSessionBridge`
- unblocks `13b` download history extraction

## 13. Anti-regression notes

- запрещено сделать coordinator новым mega-service for transport or storage
- запрещён dual-write to coordinator and legacy session state under any runtime path
