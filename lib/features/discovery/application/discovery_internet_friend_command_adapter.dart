import '../data/lan_discovery_service.dart';
import 'internet_peer_endpoint_store.dart';

class DiscoveryFriendCommandResult {
  const DiscoveryFriendCommandResult._({this.infoMessage, this.errorMessage});

  const DiscoveryFriendCommandResult.success(String message)
    : this._(infoMessage: message);

  const DiscoveryFriendCommandResult.failure(String message)
    : this._(errorMessage: message);

  final String? infoMessage;
  final String? errorMessage;

  bool get isSuccess => errorMessage == null;
}

class DiscoveryInternetFriendCommandAdapter {
  DiscoveryInternetFriendCommandAdapter({
    required InternetPeerEndpointStore internetPeerEndpointStore,
    required LanDiscoveryService lanDiscoveryService,
    void Function(String message)? log,
  }) : _internetPeerEndpointStore = internetPeerEndpointStore,
       _lanDiscoveryService = lanDiscoveryService,
       _log = log;

  final InternetPeerEndpointStore _internetPeerEndpointStore;
  final LanDiscoveryService _lanDiscoveryService;
  final void Function(String message)? _log;

  Future<DiscoveryFriendCommandResult> saveFriend({
    required String friendId,
    required String displayName,
    required String endpoint,
    bool isEnabled = true,
  }) async {
    final normalizedId = friendId.trim();
    if (normalizedId.isEmpty) {
      return const DiscoveryFriendCommandResult.failure(
        'Friend ID is required.',
      );
    }

    final parsedEndpoint = parseEndpoint(endpoint);
    if (parsedEndpoint == null) {
      return const DiscoveryFriendCommandResult.failure(
        'Endpoint must be in IPv4:port format, for example 203.0.113.7:40404.',
      );
    }

    try {
      await _internetPeerEndpointStore.saveEndpoint(
        friendId: normalizedId,
        displayName: displayName.trim(),
        endpointHost: parsedEndpoint.$1,
        endpointPort: parsedEndpoint.$2,
        isEnabled: isEnabled,
      );
      syncInternetPeers();
      return DiscoveryFriendCommandResult.success(
        'Friend saved: $normalizedId',
      );
    } catch (error) {
      final message = 'Failed to save friend: $error';
      _log?.call(message);
      return DiscoveryFriendCommandResult.failure(message);
    }
  }

  Future<DiscoveryFriendCommandResult> removeFriend(String friendId) async {
    try {
      await _internetPeerEndpointStore.removeEndpoint(friendId);
      syncInternetPeers();
      return DiscoveryFriendCommandResult.success(
        'Friend removed: ${friendId.trim()}',
      );
    } catch (error) {
      final message = 'Failed to remove friend: $error';
      _log?.call(message);
      return DiscoveryFriendCommandResult.failure(message);
    }
  }

  Future<DiscoveryFriendCommandResult> setFriendEnabled({
    required String friendId,
    required bool enabled,
  }) async {
    try {
      await _internetPeerEndpointStore.setEndpointEnabled(
        friendId: friendId,
        isEnabled: enabled,
      );
      syncInternetPeers();
      return const DiscoveryFriendCommandResult.success('');
    } catch (error) {
      final message = 'Failed to update friend: $error';
      _log?.call(message);
      return DiscoveryFriendCommandResult.failure(message);
    }
  }

  void syncInternetPeers() {
    final peers = _internetPeerEndpointStore.peers
        .where((friend) => friend.isEnabled)
        .map(
          (friend) => InternetPeerEndpoint(
            friendId: friend.friendId,
            host: friend.endpointHost,
            port: friend.endpointPort,
          ),
        )
        .toList(growable: false);
    _lanDiscoveryService.updateInternetPeers(peers);
  }

  static (String, int)? parseEndpoint(String endpoint) {
    final raw = endpoint.trim();
    if (raw.isEmpty) {
      return null;
    }

    final match = RegExp(
      r'^([0-9]{1,3}(?:\.[0-9]{1,3}){3})(?::([0-9]{1,5}))?$',
    ).firstMatch(raw);
    if (match == null) {
      return null;
    }

    final host = match.group(1)!;
    final parts = host.split('.');
    if (parts.any((part) {
      final value = int.tryParse(part);
      return value == null || value < 0 || value > 255;
    })) {
      return null;
    }

    final parsedPort =
        int.tryParse(match.group(2) ?? '') ?? LanDiscoveryService.discoveryPort;
    if (parsedPort <= 0 || parsedPort > 65535) {
      return null;
    }
    return (host, parsedPort);
  }
}
