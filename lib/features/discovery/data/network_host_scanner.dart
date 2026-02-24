import 'dart:io';

class NetworkHostScanner {
  static const List<int> _probePorts = <int>[80, 443, 22, 445, 139];
  static const int _defaultParallelism = 64;

  Future<Set<String>> scanActiveHosts() async {
    final localIps = await _getLocalIpv4Addresses();
    final candidates = <String>{};

    for (final ip in localIps) {
      candidates.addAll(_buildSubnetCandidates(ip));
    }

    candidates.removeAll(localIps);
    if (candidates.isEmpty) {
      return <String>{};
    }

    return _scanWithConcurrency(
      candidates.toList()..sort(_compareIp),
      parallelism: _defaultParallelism,
    );
  }

  Future<Set<String>> _scanWithConcurrency(
    List<String> hosts, {
    required int parallelism,
  }) async {
    final foundHosts = <String>{};
    var index = 0;

    Future<void> worker() async {
      while (true) {
        if (index >= hosts.length) {
          return;
        }

        final current = hosts[index];
        index += 1;
        final reachable = await _isHostReachable(current);
        if (reachable) {
          foundHosts.add(current);
        }
      }
    }

    final workers = <Future<void>>[];
    for (var i = 0; i < parallelism; i += 1) {
      workers.add(worker());
    }

    await Future.wait(workers);
    return foundHosts;
  }

  Future<bool> _isHostReachable(String ip) async {
    for (final port in _probePorts) {
      try {
        final socket = await Socket.connect(
          ip,
          port,
          timeout: const Duration(milliseconds: 200),
        );
        socket.destroy();
        return true;
      } on SocketException catch (error) {
        final lower = error.message.toLowerCase();
        if (lower.contains('refused')) {
          return true;
        }
      } catch (_) {
        // Keep probing other ports.
      }
    }

    return false;
  }

  Future<Set<String>> _getLocalIpv4Addresses() async {
    final interfaces = await NetworkInterface.list(
      type: InternetAddressType.IPv4,
      includeLinkLocal: false,
      includeLoopback: false,
    );

    final localIps = <String>{};
    for (final interface in interfaces) {
      for (final address in interface.addresses) {
        localIps.add(address.address);
      }
    }
    return localIps;
  }

  Set<String> _buildSubnetCandidates(String ip) {
    final parts = ip.split('.');
    if (parts.length != 4) {
      return <String>{};
    }

    final subnet = '${parts[0]}.${parts[1]}.${parts[2]}';
    final candidates = <String>{};
    for (var host = 1; host <= 254; host += 1) {
      candidates.add('$subnet.$host');
    }
    return candidates;
  }

  int _compareIp(String a, String b) {
    final aParts = a.split('.').map(int.parse).toList(growable: false);
    final bParts = b.split('.').map(int.parse).toList(growable: false);
    for (var i = 0; i < 4; i += 1) {
      final cmp = aParts[i].compareTo(bParts[i]);
      if (cmp != 0) {
        return cmp;
      }
    }
    return 0;
  }
}
