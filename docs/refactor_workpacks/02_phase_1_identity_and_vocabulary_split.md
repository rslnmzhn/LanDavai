# Workpack: Phase 1 Identity and Vocabulary Split

## 1. Scope

- Отделить local peer identity от friend/settings ownership.
- Зафиксировать vocabulary boundary для `friend`, `trusted device`, `peer`, `local peer`.
- Не входит: trust write cutover, discovery read model cutover, protocol split.

## 2. Source linkage

- `Master phase`: Phase 1
- `Depends on`: `01`
- `Unblocks`: `04`, `05`, `06`
- `Related workpacks`: `19`

## 3. Problem slice

Master plan фиксирует конфликт между `FriendRepository._localPeerIdKey`, `app_settings` и термином `friend`. Этот slice выделен отдельно, потому что без него Phase 3 будет строиться на испорченной vocabulary model.

## 4. Legacy owner and target owner

- `Legacy owner`: `FriendRepository`
- `Target owner`: `LocalPeerIdentityStore`
- `State seam closed`: local peer identity vs friend/settings ownership
- `Single write authority after cutover`: `LocalPeerIdentityStore`

## 5. Source of truth impact

- что сейчас является truth:
  - `FriendRepository._localPeerIdKey` in `app_settings`
- что станет truth:
  - `LocalPeerIdentityStore`
- что станет projection:
  - UI labels and grouped peer lists
- что станет cache:
  - none
- что станет temporary bridge only:
  - `PeerVocabularyAdapter`

## 6. Read/write cutover

- `Legacy read path`: `FriendRepository.loadOrCreateLocalPeerId`
- `Target read path`: `LocalPeerIdentityStore`
- `Read switch point`: app bootstrap and any peer self-identification stop reading through `FriendRepository`
- `Legacy write path`: `FriendRepository` writes `local_peer_id` into `app_settings`
- `Target write path`: `LocalPeerIdentityStore` only
- `Write switch point`: first commit where local identity creation no longer routes through `FriendRepository`
- `Dual-read allowed?`: yes, against the same stored key during transition validation only
- `Dual-write allowed?`: no

## 7. Temporary bridge

- `Bridge name`: `PeerVocabularyAdapter`
- `Why it exists`: keep old UI wording from collapsing trust and internet endpoint models while terminology is cleaned up
- `Phase introduced`: Phase 1
- `Max allowed lifetime`: through Phase 3 only
- `Deletion phase`: end of Phase 3
- `Forbidden long-term use`: cannot become permanent merged peer facade

## 8. Concrete migration steps

1. зафиксировать, что `friend` больше не означает trusted LAN device
2. выделить local identity как отдельный ownership seam
3. перевести bootstrap read path на `LocalPeerIdentityStore`
4. запретить новые write paths в `FriendRepository` для local identity
5. ограничить `PeerVocabularyAdapter` только naming/projection use
6. прогнать repository contract и identity mapping tests
7. зафиксировать deletion proof для `_localPeerIdKey` ownership inside `FriendRepository`

## 9. Evidence and source anchors

- `Evidence level`: Confirmed from code
- `Source of truth`:
  - `docs/refactor_master_plan.md`
  - `lib/features/discovery/data/friend_repository.dart` / `_localPeerIdKey`, `loadOrCreateLocalPeerId`, `listFriends`, `setFriendEnabled`
  - `lib/features/settings/data/app_settings_repository.dart` / `load`, `save`
  - `lib/core/storage/app_database.dart` / `appSettingsTable`, `friendsTable`

## 10. Test gate

- До начала нужны: repository contract tests for `friends` and `app_settings`
- Подтверждают cutover: identity mapping tests, migration regression covering local peer bootstrap
- Hard stop failure:
  - local peer identity still mutates through `FriendRepository` after cutover

## 11. Completion criteria

- `LocalPeerIdentityStore` declared as sole writer
- `FriendRepository` is no longer the conceptual owner of local identity
- vocabulary in active planning/docs stops using `friend` as LAN-trust synonym

## 12. Deletions unlocked

- conceptual ownership of `_localPeerIdKey` by `FriendRepository`
- actual repository-side cleanup may still be blocked by downstream implementation work

## 13. Anti-regression notes

- запрещён новый generic `peer` API, который снова смешает trust и friend
- запрещён dual-write между `FriendRepository` и `LocalPeerIdentityStore`
