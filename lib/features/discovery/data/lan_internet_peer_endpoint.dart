class InternetPeerEndpoint {
  const InternetPeerEndpoint({
    required this.friendId,
    required this.host,
    required this.port,
  });

  final String friendId;
  final String host;
  final int port;
}
