# Workpack: Phase 1 Local Peer Identity and Vocabulary Baseline

## 1. Scope

- Зафиксировать vocabulary boundary для `friend`, `trusted device`, `peer`, `local peer`.
- Вынести local peer identity из conceptual ownership `FriendRepository` в `LocalPeerIdentityStore`.
- Не входит: `InternetPeerEndpointStore`, `SettingsStore`, discovery read-model cutover, trust write cutover.

## 2. Source linkage

- `Master phase`: Phase 1
- `Depends on`: `01`
- `Unblocks`: `03a`, `03b`, `03`
- `Related workpacks`: `19`

## 3. Problem slice

Master plan фиксирует, что `FriendRepository._localPeerIdKey` смешивает local peer identity с friend semantics и `app_settings`. Этот slice выделен отдельно, потому что без него Phase 1 не замыкает vocabulary boundary и later ownership workpacks стартуют с уже испорченным словарём.

## 4. Legacy owner and target owner

- `Legacy owner`: `FriendRepository`
- `Target owner`: `LocalPeerIdentityStore`
- `State seam closed`: local peer identity vs friend/settings ownership
- `Single write authority after cutover`: `LocalPeerIdentityStore`
- `Forbidden writers`: `FriendRepository`, `DiscoveryController`, settings UI callbacks, any helper that writes `local_peer_id` directly into `app_settings`
- `Forbidden dual-write paths`: `FriendRepository.loadOrCreateLocalPeerId` in parallel with `LocalPeerIdentityStore`; any path that writes local identity through both `friends` semantics and `app_settings`

## 5. Source of truth impact

- что сейчас является truth:
  - `FriendRepository._localPeerIdKey` persisted in `app_settings`
- что станет truth:
  - `LocalPeerIdentityStore`
- что станет projection:
  - UI labels and grouped peer lists only
- что станет cache:
  - none
- что станет temporary bridge only:
  - `PeerVocabularyAdapter`

## 6. Read/write cutover

- `Legacy read path`: `FriendRepository.loadOrCreateLocalPeerId`
- `Target read path`: `LocalPeerIdentityStore`
- `Read switch point`: bootstrap and self-identification flows stop reading local identity through `FriendRepository`
- `Legacy write path`: `FriendRepository` writes `local_peer_id` into `app_settings`
- `Target write path`: `LocalPeerIdentityStore` only
- `Write switch point`: first commit where local identity creation and lookup no longer route through `FriendRepository`
- `Dual-read allowed?`: yes, against the same persisted key during parity validation only
- `Dual-write allowed?`: no

## 7. Temporary bridge

- `Bridge name`: `PeerVocabularyAdapter`
- `Why it exists`: keep old UI wording stable while `friend`, `trusted device`, `internet peer`, and `local peer` are separated conceptually
- `Phase introduced`: Phase 1
- `Max allowed lifetime`: through Phase 3 only
- `Deletion phase`: `20_phase_3_discovery_controller_legacy_field_downgrade.md`
- `Forbidden long-term use`: cannot remain as a permanent merged peer facade

## 8. Concrete migration steps

1. зафиксировать, что `friend` больше не означает trusted LAN device
2. выделить local identity как отдельный ownership seam
3. перевести bootstrap read path на `LocalPeerIdentityStore`
4. запретить новые local identity writes в `FriendRepository`
5. ограничить `PeerVocabularyAdapter` only projection and naming cleanup
6. прогнать `GATE-01` и `GATE-03`
7. зафиксировать deletion proof для conceptual ownership `_localPeerIdKey` inside `FriendRepository`

## 9. Evidence and source anchors

- `Evidence level`: Confirmed from code
- `Source of truth`:
  - `docs/refactor_master_plan.md`
  - `lib/features/discovery/data/friend_repository.dart` / `FriendRepository`, `_localPeerIdKey`, `loadOrCreateLocalPeerId`, `listFriends`, `setFriendEnabled`
  - `lib/features/settings/data/app_settings_repository.dart` / `AppSettingsRepository`, `load`, `save`
  - `lib/core/storage/app_database.dart` / `appSettingsTable`, `friendsTable`
- `Compatibility anchors`:
  - `app_settings`
  - `friends`

## 10. Test gate

- `До начала нужны`: `GATE-01`, `GATE-03`
- `Подтверждают cutover`: local peer bootstrap still resolves one stable identity without `FriendRepository` ownership
- `Hard stop failure`: any production path still writes local identity through `FriendRepository`

## 11. Completion criteria

- `LocalPeerIdentityStore` is declared and used as sole local identity writer
- `FriendRepository` no longer owns conceptual local identity contract
- active planning/docs stop using `friend` as LAN-trust synonym

## 12. Deletions unlocked

- conceptual ownership of `_localPeerIdKey` by `FriendRepository`
- prepares deletion of `PeerVocabularyAdapter` in `20`

## 13. Anti-regression notes

- запрещён новый generic `peer` API, который снова смешает trust и friend
- запрещён dual-write between `FriendRepository` and `LocalPeerIdentityStore`
