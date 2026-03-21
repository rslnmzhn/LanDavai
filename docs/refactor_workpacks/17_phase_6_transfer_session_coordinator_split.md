# Workpack: Phase 6 Transfer Session Coordinator Split

## 1. Scope

- Вынести runtime transfer/session ownership в `TransferSessionCoordinator`.
- Разорвать split session control between controller, protocol service and transfer services.
- Не входит: packet codec/transport extraction; они already covered in Phase 4 workpacks.

## 2. Source linkage

- `Master phase`: Phase 6
- `Depends on`: `09`, `06`, `01`
- `Unblocks`: `23`, `18`
- `Related workpacks`: `07`, `08`

## 3. Problem slice

Master plan фиксирует, что transfer negotiation and runtime session state fragmented across protocol callbacks and service execution. Этот slice выделен отдельно, потому что live session owner должен быть один до удаления implicit callback mesh.

## 4. Legacy owner and target owner

- `Legacy owner`: `DiscoveryController` plus protocol/service glue
- `Target owner`: `TransferSessionCoordinator`
- `State seam closed`: session orchestration separate from transport and file execution
- `Single write authority after cutover`: `TransferSessionCoordinator`

## 5. Source of truth impact

- что сейчас является truth:
  - mixed controller callbacks, protocol sends and transfer service state transitions
- что станет truth:
  - `TransferSessionCoordinator`
- что станет projection:
  - transfer progress/status cards and history read-models
- что станет cache:
  - `transfer_history` remains durable history, not live session truth
- что станет temporary bridge only:
  - `TransferSessionBridge`

## 6. Read/write cutover

- `Legacy read path`: UI and services consult mixed controller/service state
- `Target read path`: UI and related services consult coordinator session model
- `Read switch point`: no active session view depends on controller-owned runtime state
- `Legacy write path`: request/decision/progress/finalize steps mutate session state through multiple actors
- `Target write path`: session lifecycle transitions go through coordinator only
- `Write switch point`: accept/reject/start/finalize and progress updates stop mutating mixed session state
- `Dual-read allowed?`: yes, for session continuity regression only
- `Dual-write allowed?`: no

## 7. Temporary bridge

- `Bridge name`: `TransferSessionBridge`
- `Why it exists`: preserve live transfer flows while session authority is consolidated
- `Phase introduced`: Phase 6
- `Max allowed lifetime`: through Phase 6 only
- `Deletion phase`: this workpack
- `Forbidden long-term use`: cannot leave session ownership split between coordinator and legacy actors

## 8. Concrete migration steps

1. inventory session lifecycle transitions across controller/protocol/service glue
2. route session creation/decision/progress/finalization through coordinator
3. switch UI/session readers to coordinator projection
4. keep transport and file execution behind command/result boundaries only
5. run session continuity and protocol compatibility tests
6. delete bridge after end-to-end proof

## 9. Evidence and source anchors

- `Evidence level`: Strong inference from code structure
- `Source of truth`:
  - `docs/refactor_master_plan.md`
  - `lib/features/discovery/application/discovery_controller.dart` / `_onTransferRequest`, `_onTransferDecision`
  - `lib/features/discovery/data/lan_discovery_service.dart` / `sendTransferRequest`, `sendTransferDecision`
  - `lib/features/transfer/data/file_transfer_service.dart` / `startReceiver`, `sendFiles`
  - `lib/features/transfer/data/video_link_share_service.dart` / `activeSession`

## 10. Test gate

- До начала нужны: session continuity tests, protocol compatibility tests
- Подтверждают cutover: inbound and outbound sessions complete under coordinator-owned runtime state
- Hard stop failure:
  - any active transfer still depends on controller-owned session truth after cutover

## 11. Completion criteria

- `TransferSessionCoordinator` is the only session writer
- transport and execution services no longer own session truth
- `TransferSessionBridge` is deleted

## 12. Deletions unlocked

- implicit controller/protocol session ownership paths
- `TransferSessionBridge`

## 13. Anti-regression notes

- запрещено сделать coordinator новым mega-service for transport/storage
- запрещён dual-write to coordinator and legacy session state under any runtime path
