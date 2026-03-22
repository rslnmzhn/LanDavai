import 'lan_packet_codec.dart';
import 'lan_protocol_events.dart';

class PresenceHandlingResult {
  const PresenceHandlingResult({
    this.detectedEvent,
    this.shouldRespondToDiscover = false,
  });

  final AppPresenceEvent? detectedEvent;
  final bool shouldRespondToDiscover;
}

class LanPresenceProtocolHandler {
  const LanPresenceProtocolHandler();

  PresenceHandlingResult handlePresencePacket({
    required LanDiscoveryPresencePacket packet,
    required String senderIp,
    required DateTime observedAt,
  }) {
    if (packet.prefix == LanPacketCodec.discoverPrefix) {
      return const PresenceHandlingResult(shouldRespondToDiscover: true);
    }
    if (packet.prefix != LanPacketCodec.responsePrefix) {
      return const PresenceHandlingResult();
    }
    return PresenceHandlingResult(
      detectedEvent: AppPresenceEvent(
        ip: senderIp,
        deviceName: packet.deviceName,
        operatingSystem: packet.operatingSystem,
        deviceType: packet.deviceType,
        peerId: packet.peerId,
        observedAt: observedAt,
      ),
    );
  }
}
