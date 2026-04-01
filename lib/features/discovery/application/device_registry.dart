import 'package:flutter/foundation.dart';

import '../data/device_alias_repository.dart';

class DeviceRegistry extends ChangeNotifier {
  DeviceRegistry({required DeviceAliasRepository deviceAliasRepository})
    : _deviceAliasRepository = deviceAliasRepository;

  final DeviceAliasRepository _deviceAliasRepository;

  final Map<String, String> _aliasByMac = <String, String>{};
  final Map<String, String> _lastKnownIpByMac = <String, String>{};
  final Map<String, String> _macByLastKnownIp = <String, String>{};

  Map<String, String> get aliases =>
      Map<String, String>.unmodifiable(_aliasByMac);

  String? aliasForMac(String? macAddress) {
    final normalizedMac = DeviceAliasRepository.normalizeMac(macAddress);
    if (normalizedMac == null) {
      return null;
    }
    return _aliasByMac[normalizedMac];
  }

  String? macForIp(String? ip) {
    final normalizedIp = ip?.trim();
    if (normalizedIp == null || normalizedIp.isEmpty) {
      return null;
    }
    return _macByLastKnownIp[normalizedIp];
  }

  Future<void> load() async {
    final aliases = await _deviceAliasRepository.loadAliasMap();
    final lastKnownIps = await _deviceAliasRepository.loadLastKnownIpMap();

    _aliasByMac
      ..clear()
      ..addAll(aliases);
    _replaceLastKnownIpMappings(lastKnownIps);
    notifyListeners();
  }

  Future<void> recordSeenDevices(Map<String, String> macToIp) async {
    if (macToIp.isEmpty) {
      return;
    }

    await _deviceAliasRepository.recordSeenDevices(macToIp);
    for (final entry in macToIp.entries) {
      final normalizedMac = DeviceAliasRepository.normalizeMac(entry.key);
      final normalizedIp = entry.value.trim();
      if (normalizedMac == null || normalizedIp.isEmpty) {
        continue;
      }
      _setLastKnownIp(normalizedMac, normalizedIp);
    }
    notifyListeners();
  }

  Future<void> setAlias({
    required String macAddress,
    required String alias,
  }) async {
    final normalizedMac = DeviceAliasRepository.normalizeMac(macAddress);
    if (normalizedMac == null) {
      throw ArgumentError('Invalid MAC address: $macAddress');
    }

    final normalizedAlias = alias.trim();
    await _deviceAliasRepository.setAlias(
      macAddress: normalizedMac,
      alias: normalizedAlias,
    );

    if (normalizedAlias.isEmpty) {
      _aliasByMac.remove(normalizedMac);
    } else {
      _aliasByMac[normalizedMac] = normalizedAlias;
    }
    notifyListeners();
  }

  void _replaceLastKnownIpMappings(Map<String, String> lastKnownIps) {
    _lastKnownIpByMac.clear();
    _macByLastKnownIp.clear();
    for (final entry in lastKnownIps.entries) {
      final normalizedMac = DeviceAliasRepository.normalizeMac(entry.key);
      final normalizedIp = entry.value.trim();
      if (normalizedMac == null || normalizedIp.isEmpty) {
        continue;
      }
      _lastKnownIpByMac[normalizedMac] = normalizedIp;
      _macByLastKnownIp[normalizedIp] = normalizedMac;
    }
  }

  void _setLastKnownIp(String macAddress, String ip) {
    final previousIp = _lastKnownIpByMac[macAddress];
    if (previousIp != null && previousIp != ip) {
      _macByLastKnownIp.remove(previousIp);
    }
    _lastKnownIpByMac[macAddress] = ip;
    _macByLastKnownIp[ip] = macAddress;
  }
}
