import 'package:flutter/foundation.dart';

import 'device_registry.dart';
import '../data/device_alias_repository.dart';

class TrustedLanPeerStore extends ChangeNotifier {
  TrustedLanPeerStore({
    required DeviceRegistry deviceRegistry,
    required DeviceAliasRepository deviceAliasRepository,
  }) : _deviceRegistry = deviceRegistry,
       _deviceAliasRepository = deviceAliasRepository;

  final DeviceRegistry _deviceRegistry;
  final DeviceAliasRepository _deviceAliasRepository;

  final Set<String> _trustedMacs = <String>{};

  Set<String> get trustedMacs => Set<String>.unmodifiable(_trustedMacs);

  bool isTrustedMac(String? macAddress) {
    final normalizedMac = DeviceAliasRepository.normalizeMac(macAddress);
    if (normalizedMac == null) {
      return false;
    }
    return _trustedMacs.contains(normalizedMac);
  }

  bool isTrustedIp(String? ip) {
    final macAddress = _deviceRegistry.macForIp(ip);
    return isTrustedMac(macAddress);
  }

  Future<void> load() async {
    final trustedMacs = await _deviceAliasRepository.loadTrustedMacs();
    _trustedMacs
      ..clear()
      ..addAll(trustedMacs);
    notifyListeners();
  }

  Future<void> trustDevice({required String macAddress}) async {
    await _setTrusted(macAddress: macAddress, isTrusted: true);
  }

  Future<void> revokeTrust({required String macAddress}) async {
    await _setTrusted(macAddress: macAddress, isTrusted: false);
  }

  Future<void> _setTrusted({
    required String macAddress,
    required bool isTrusted,
  }) async {
    final normalizedMac = DeviceAliasRepository.normalizeMac(macAddress);
    if (normalizedMac == null) {
      throw ArgumentError('Invalid MAC address: $macAddress');
    }

    await _deviceAliasRepository.setTrusted(
      macAddress: normalizedMac,
      isTrusted: isTrusted,
    );

    if (isTrusted) {
      _trustedMacs.add(normalizedMac);
    } else {
      _trustedMacs.remove(normalizedMac);
    }
    notifyListeners();
  }
}
