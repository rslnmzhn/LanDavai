# Workpack: Phase 4 Packet Codec Split

## 1. Scope

- Вынести packet encode/decode authority из `LanDiscoveryService`.
- Оставить wire semantics неизменными.
- Не входит: transport lifecycle extraction, scenario handler split, facade deletion.

## 2. Source linkage

- `Master phase`: Phase 4
- `Depends on`: `01`, `06`
- `Unblocks`: `09`, `21`
- `Related workpacks`: `07`

## 3. Problem slice

Master plan фиксирует, что packet constants, serialization и decode logic сидят в одном infra-class. Этот slice выделен отдельно, потому что codec parity нужно проверять независимо от transport ownership.

## 4. Legacy owner and target owner

- `Legacy owner`: `LanDiscoveryService`
- `Target owner`: packet codec set
- `State seam closed`: wire serialization separate from transport and application orchestration
- `Single write authority after cutover`: packet codec set for encode/decode semantics

## 5. Source of truth impact

- что сейчас является truth:
  - packet encode/decode logic inside `LanDiscoveryService`
- что станет truth:
  - packet codec set
- что станет projection:
  - none
- что станет cache:
  - none
- что станет temporary bridge only:
  - `ProtocolDispatchFacade`

## 6. Read/write cutover

- `Legacy read path`: incoming packets decoded by service-internal helpers
- `Target read path`: handlers decode through codec set
- `Read switch point`: no packet decode path depends on service-internal codec methods
- `Legacy write path`: outgoing packet payloads built in `LanDiscoveryService`
- `Target write path`: packet payloads built through codec set
- `Write switch point`: all send flows build envelopes via codec set
- `Dual-read allowed?`: yes, in parity tests only
- `Dual-write allowed?`: no

## 7. Temporary bridge

- `Bridge name`: `ProtocolDispatchFacade`
- `Why it exists`: keep public send/decode surface stable during codec extraction
- `Phase introduced`: Phase 4
- `Max allowed lifetime`: through Phase 4 only
- `Deletion phase`: `21_phase_4_protocol_dispatch_facade_removal.md`
- `Forbidden long-term use`: cannot keep service-internal codecs alive behind wrapper methods

## 8. Concrete migration steps

1. inventory packet constants and envelope helpers
2. route encode/decode through codec set
3. compare old/new decode outputs under protocol parity tests
4. freeze packet identifiers and envelope semantics
5. mark service-internal codec paths as legacy-only pending deletion

## 9. Evidence and source anchors

- `Evidence level`: Confirmed from code
- `Source of truth`:
  - `docs/refactor_master_plan.md`
  - `lib/features/discovery/data/lan_discovery_service.dart` / packet constants, `_decodeTransferEnvelope`, send methods

## 10. Test gate

- До начала нужны: protocol compatibility tests
- Подтверждают cutover: encode/decode parity for existing packet families
- Hard stop failure:
  - packet payload shape drifts from current wire contract

## 11. Completion criteria

- packet encode/decode authority no longer lives in `LanDiscoveryService`
- packet identifiers and envelope semantics remain unchanged

## 12. Deletions unlocked

- prepares removal of service-internal codec helpers in `21`

## 13. Anti-regression notes

- запрещено менять packet identifiers как побочный эффект “чистки”
- запрещён helper split, если write authority остаётся в `LanDiscoveryService`
