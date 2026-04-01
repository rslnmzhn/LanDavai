import 'lan_packet_codec_common.dart';
import 'lan_packet_codec_models.dart';
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
    if (packet.prefix == lanDiscoverPrefix) {
      return const PresenceHandlingResult(shouldRespondToDiscover: true);
    }
    if (packet.prefix != lanResponsePrefix) {
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
