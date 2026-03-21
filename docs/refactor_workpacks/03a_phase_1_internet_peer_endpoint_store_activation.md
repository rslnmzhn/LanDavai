# Workpack: Phase 1 InternetPeerEndpointStore Activation

## 1. Scope

- Активировать `InternetPeerEndpointStore` как единственный owner persistent internet endpoint records.
- Отделить internet endpoint ownership от local peer identity и LAN trust.
- Не входит: trust write authority, discovery read-model cutover, settings ownership.

## 2. Source linkage

- `Master phase`: Phase 1
- `Depends on`: `01`, `02`
- `Unblocks`: `06`, `20`
- `Related workpacks`: `03b`, `05`

## 3. Problem slice

Master plan фиксирует, что `friends` durable records и local peer identity живут в одной repository surface. Этот slice выделен отдельно, потому что internet endpoints должны получить своего владельца до discovery read-side cutover.

## 4. Legacy owner and target owner

- `Legacy owner`: `FriendRepository`
- `Target owner`: `InternetPeerEndpointStore`
- `State seam closed`: internet endpoint persistence separate from local identity and LAN trust
- `Single write authority after cutover`: `InternetPeerEndpointStore`
- `Forbidden writers`: `DiscoveryController`, widgets, `TrustedLanPeerStore`, any direct `FriendRepository` write path outside the store boundary
- `Forbidden dual-write paths`: direct `friends` writes in parallel with `InternetPeerEndpointStore`; mirrored writes from trusted-device flows into `friends`

## 5. Source of truth impact

- что сейчас является truth:
  - `FriendRepository` over `friends`
- что станет truth:
  - `InternetPeerEndpointStore`
- что станет projection:
  - discovery and peer-list UI projections
- что станет cache:
  - none beyond store-owned read snapshots
- что станет temporary bridge only:
  - `PeerVocabularyAdapter`

## 6. Read/write cutover

- `Legacy read path`: friend/internet endpoint reads go through `FriendRepository`
- `Target read path`: endpoint reads go through `InternetPeerEndpointStore`
- `Read switch point`: discovery and peer-management flows stop reading persistent internet endpoints through raw repository calls
- `Legacy write path`: `upsertFriend`, `setFriendEnabled`, remove/update operations on `FriendRepository`
- `Target write path`: `InternetPeerEndpointStore` only
- `Write switch point`: endpoint enable/disable and endpoint mutation stop bypassing the store
- `Dual-read allowed?`: yes, against the same `friends` table during parity validation only
- `Dual-write allowed?`: no

## 7. Temporary bridge

- `Bridge name`: `PeerVocabularyAdapter`
- `Why it exists`: keep old peer wording stable while internet endpoint semantics are separated from trust semantics
- `Phase introduced`: Phase 1
- `Max allowed lifetime`: through Phase 3 only
- `Deletion phase`: `20_phase_3_discovery_controller_legacy_field_downgrade.md`
- `Forbidden long-term use`: cannot remain as unified peer facade over LAN trust and internet endpoints

## 8. Concrete migration steps

1. freeze the rule that `friends` means persistent internet endpoint records only
2. route endpoint reads through `InternetPeerEndpointStore`
3. route endpoint writes through `InternetPeerEndpointStore`
4. forbid any trust-related write from entering `friends`
5. keep temporary dual-read only for parity checks
6. run `GATE-01` and `GATE-07`
7. capture proof that `FriendRepository` is no longer the business owner of internet endpoints

## 9. Evidence and source anchors

- `Evidence level`: Confirmed from code
- `Source of truth`:
  - `docs/refactor_master_plan.md`
  - `lib/features/discovery/data/friend_repository.dart` / `FriendRepository`, `listFriends`, `upsertFriend`, `setFriendEnabled`
  - `lib/features/discovery/domain/friend_peer.dart` / `FriendPeer`
  - `lib/core/storage/app_database.dart` / `friendsTable`
- `Compatibility anchors`:
  - `friends`

## 10. Test gate

- `До начала нужны`: `GATE-01`, `GATE-07`
- `Подтверждают cutover`: endpoint enable/disable and list operations preserve `friends` semantics under the store boundary
- `Hard stop failure`: any production internet endpoint write still bypasses `InternetPeerEndpointStore`

## 11. Completion criteria

- `InternetPeerEndpointStore` is the sole writer for persistent endpoint records
- `FriendRepository` remains a persistence adapter only, not the business owner
- discovery read-side can consume explicit internet endpoint projections later in `06`

## 12. Deletions unlocked

- prepares deletion of `DiscoveryController._friends` as business truth in `20`
- contributes to deletion of `PeerVocabularyAdapter` in `20`

## 13. Anti-regression notes

- запрещено снова трактовать trusted LAN device as `friends` row
- запрещён direct `FriendRepository` callback path that bypasses the store
