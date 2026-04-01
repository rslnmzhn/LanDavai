import 'package:flutter/foundation.dart';

import '../data/friend_repository.dart';
import '../domain/friend_peer.dart';

class InternetPeerEndpointStore extends ChangeNotifier {
  InternetPeerEndpointStore({required FriendRepository friendRepository})
    : _friendRepository = friendRepository;

  final FriendRepository _friendRepository;

  final List<FriendPeer> _peers = <FriendPeer>[];

  List<FriendPeer> get peers => List<FriendPeer>.unmodifiable(_peers);

  Future<void> load() async {
    final peers = await _friendRepository.listFriends();
    _peers
      ..clear()
      ..addAll(peers);
    notifyListeners();
  }

  Future<void> saveEndpoint({
    required String friendId,
    required String displayName,
    required String endpointHost,
    required int endpointPort,
    required bool isEnabled,
  }) async {
    await _friendRepository.upsertFriend(
      friendId: friendId,
      displayName: displayName,
      endpointHost: endpointHost,
      endpointPort: endpointPort,
      isEnabled: isEnabled,
    );
    await load();
  }

  Future<void> removeEndpoint(String friendId) async {
    await _friendRepository.removeFriend(friendId);
    await load();
  }

  Future<void> setEndpointEnabled({
    required String friendId,
    required bool isEnabled,
  }) async {
    await _friendRepository.setFriendEnabled(
      friendId: friendId,
      isEnabled: isEnabled,
    );
    await load();
  }
}
