import 'package:flutter/foundation.dart';

import '../data/discovery_network_interface_catalog.dart';
import 'discovery_network_scope.dart';
import 'discovery_network_scope_grouper.dart';

class DiscoveryNetworkScopeStore extends ChangeNotifier {
  DiscoveryNetworkScopeStore({
    required DiscoveryNetworkInterfaceCatalog interfaceCatalog,
    DiscoveryNetworkScopeGrouper? grouper,
  }) : _interfaceCatalog = interfaceCatalog,
       _grouper = grouper ?? DiscoveryNetworkScopeGrouper();

  static const String allScopeId = DiscoveryNetworkScopeGrouper.allScopeId;

  final DiscoveryNetworkInterfaceCatalog _interfaceCatalog;
  final DiscoveryNetworkScopeGrouper _grouper;

  DiscoveryNetworkScopeSnapshot _snapshot = const DiscoveryNetworkScopeSnapshot(
    ranges: <DiscoveryNetworkRange>[],
    allLocalIps: <String>[],
    preferredIp: null,
  );
  String _selectedScopeId = allScopeId;

  List<DiscoveryNetworkRange> get ranges => _snapshot.ranges;
  String get selectedScopeId => _selectedScopeId;
  DiscoveryNetworkRange? get selectedRange {
    if (_selectedScopeId == allScopeId) {
      return null;
    }
    for (final range in _snapshot.ranges) {
      if (range.id == _selectedScopeId) {
        return range;
      }
    }
    return null;
  }

  Set<String> get activeLocalIps => Set<String>.unmodifiable(
    selectedRange?.localIps ?? _snapshot.allLocalIps,
  );

  String? get preferredLocalIp =>
      selectedRange?.preferredIp ?? _snapshot.preferredIp;

  Future<void> refresh() async {
    final interfaces = await _interfaceCatalog.loadIpv4Interfaces();
    final nextSnapshot = _grouper.group(interfaces);
    var nextSelectedScopeId = _selectedScopeId;
    if (nextSelectedScopeId != allScopeId &&
        !nextSnapshot.ranges.any((range) => range.id == nextSelectedScopeId)) {
      nextSelectedScopeId = allScopeId;
    }
    final changed =
        nextSnapshot != _snapshot || nextSelectedScopeId != _selectedScopeId;
    _snapshot = nextSnapshot;
    _selectedScopeId = nextSelectedScopeId;
    if (changed) {
      notifyListeners();
    }
  }

  bool selectScope(String scopeId) {
    final nextScopeId = scopeId.trim();
    if (nextScopeId.isEmpty) {
      return false;
    }
    if (nextScopeId != allScopeId &&
        !_snapshot.ranges.any((range) => range.id == nextScopeId)) {
      return false;
    }
    if (_selectedScopeId == nextScopeId) {
      return false;
    }
    _selectedScopeId = nextScopeId;
    notifyListeners();
    return true;
  }

  bool matchesSelectedScope(String ip) {
    if (_selectedScopeId == allScopeId) {
      return true;
    }
    return _grouper.rangeIdForIp(ip) == _selectedScopeId;
  }
}
