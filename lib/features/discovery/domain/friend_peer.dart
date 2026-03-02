class FriendPeer {
  const FriendPeer({
    required this.friendId,
    required this.displayName,
    required this.endpointHost,
    required this.endpointPort,
    required this.isEnabled,
    required this.updatedAtMs,
  });

  final String friendId;
  final String displayName;
  final String endpointHost;
  final int endpointPort;
  final bool isEnabled;
  final int updatedAtMs;

  String get endpoint => '$endpointHost:$endpointPort';
}
