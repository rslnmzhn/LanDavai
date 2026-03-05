import 'dart:developer' as developer;
import 'dart:io';

class NetworkHostScanner {
  static const List<int> _probePorts = <int>[445, 139, 22, 53, 80, 443];
  static const int _defaultParallelism = 48;
  static const Duration _probeTimeout = Duration(milliseconds: 220);
  static const Duration _arpPrimeDelay = Duration(milliseconds: 600);
  static const List<String> _virtualInterfaceHints = <String>[
    'loopback',
    'docker',
    'vmware',
    'virtual',
    'vethernet',
    'hyper-v',
    'vbox',
    'wsl',
    'tailscale',
    'zerotier',
    'hamachi',
    'tun',
    'tap',
    'bridge',
  ];

  NetworkHostScanner({this.allowTcpFallback = false});

  final bool allowTcpFallback;

  Future<Map<String, String?>> scanActiveHosts({
    String? preferredSourceIp,
  }) async {
    final localIps = await _getLocalIpv4Addresses(
      preferredSourceIp: preferredSourceIp,
    );
    final candidates = <String>{};

    for (final ip in localIps) {
      candidates.addAll(_buildSubnetCandidates(ip));
    }

    candidates.removeAll(localIps);
    if (candidates.isEmpty) {
      _log('No scan candidates. localIps=$localIps');
      return <String, String?>{};
    }

    _log(
      'Starting scan. localIps=${localIps.length}, '
      'candidates=${candidates.length}, parallelism=$_defaultParallelism',
    );

    final arpPreferredSourceIp = Platform.isAndroid || localIps.length > 1
        ? null
        : preferredSourceIp;
    final arpHosts = await _scanUsingNeighborTable(
      candidates,
      preferredSourceIp: arpPreferredSourceIp,
    );
    if (arpHosts.isNotEmpty) {
      _log('Neighbor-table scan complete. reachable=${arpHosts.length}');
      return arpHosts;
    }

    if (!allowTcpFallback) {
      _log('Neighbor-table scan returned 0 hosts. TCP fallback disabled.');
      return <String, String?>{};
    }

    _log('Neighbor-table scan returned 0 hosts. Fallback to TCP probing.');
    final foundHosts = await _scanWithTcpProbing(
      candidates.toList()..sort(_compareIp),
      parallelism: _defaultParallelism,
    );
    _log('TCP fallback complete. reachable=${foundHosts.length}');
    return <String, String?>{for (final ip in foundHosts) ip: null};
  }

  Future<Map<String, String>> _scanUsingNeighborTable(
    Set<String> candidates, {
    String? preferredSourceIp,
  }) async {
    await _primeNeighborCache(candidates);
    final arpByIp = await _loadArpEntries(preferredSourceIp: preferredSourceIp);
    if (arpByIp.isEmpty) {
      _log('ARP table is empty or unreadable.');
      return <String, String>{};
    }

    final rawHosts = <String>{};
    final hostMacs = <String, String>{};
    for (final ip in candidates) {
      final mac = arpByIp[ip];
      if (mac == null) {
        continue;
      }
      rawHosts.add(ip);
      hostMacs[ip] = mac;
    }

    if (rawHosts.isEmpty) {
      return <String, String>{};
    }

    final filteredHosts = _filterProxyArpNoise(rawHosts, hostMacs);
    final result = <String, String>{};
    for (final ip in filteredHosts) {
      final mac = hostMacs[ip];
      if (mac != null) {
        result[ip] = mac;
      }
    }
    return result;
  }

  Future<void> _primeNeighborCache(Set<String> candidates) async {
    RawDatagramSocket? socket;
    try {
      socket = await RawDatagramSocket.bind(InternetAddress.anyIPv4, 0);
      final payload = <int>[0];
      final sortedCandidates = candidates.toList()..sort(_compareIp);
      for (final ip in sortedCandidates) {
        socket.send(payload, InternetAddress(ip), 9);
      }
      await Future<void>.delayed(_arpPrimeDelay);
      _log('Neighbor cache primed via UDP probe.');
    } catch (error) {
      _log('Failed to prime neighbor cache: $error');
    } finally {
      socket?.close();
    }
  }

  Set<String> _filterProxyArpNoise(
    Set<String> hosts,
    Map<String, String> hostMacs,
  ) {
    final countByMac = <String, int>{};
    for (final mac in hostMacs.values) {
      countByMac[mac] = (countByMac[mac] ?? 0) + 1;
    }
    if (countByMac.isEmpty) {
      return hosts;
    }

    final sorted = countByMac.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));
    final dominant = sorted.first;
    final dominantShare = dominant.value / hosts.length;
    if (dominant.value < 20 || dominantShare < 0.70) {
      return hosts;
    }

    final dominantMac = dominant.key;
    final dominantIps =
        hosts.where((ip) => hostMacs[ip] == dominantMac).toList(growable: false)
          ..sort(_compareIp);

    if (dominantIps.isEmpty) {
      return hosts;
    }

    final filtered = <String>{};
    for (final ip in hosts) {
      if (hostMacs[ip] != dominantMac) {
        filtered.add(ip);
      }
    }

    filtered.add(dominantIps.first);
    _log(
      'Proxy-ARP noise detected: dominantMac=$dominantMac '
      'hosts=${dominant.value}/${hosts.length}. '
      'Filtered to ${filtered.length} hosts.',
    );
    return filtered;
  }

  Future<Map<String, String>> _loadArpEntries({
    String? preferredSourceIp,
  }) async {
    if (Platform.isLinux || Platform.isAndroid) {
      final fromProc = await _loadArpFromProc(
        preferredSourceIp: preferredSourceIp,
      );
      if (fromProc.isNotEmpty) {
        _log('Loaded ARP entries from /proc/net/arp: ${fromProc.length}');
        return fromProc;
      }
    }

    final commandPlans = <List<String>>[
      if (Platform.isWindows) <String>['arp', '-a'],
      if (!Platform.isWindows) <String>['arp', '-an'],
      if (!Platform.isWindows) <String>['arp', '-a'],
      if (!Platform.isWindows) <String>['ip', 'neigh'],
    ];

    for (final plan in commandPlans) {
      final executable = plan.first;
      final args = plan.sublist(1);
      try {
        final result = await Process.run(executable, args);
        if (result.exitCode != 0) {
          _log('$executable ${args.join(" ")} failed: ${result.stderr}');
          continue;
        }

        final output = result.stdout.toString();
        final parsed = _parseArpOutput(
          output,
          preferredSourceIp: preferredSourceIp,
        );
        if (parsed.isNotEmpty) {
          _log(
            'Loaded ARP entries using "$executable ${args.join(" ")}": '
            '${parsed.length}',
          );
          return parsed;
        }
        if (Platform.isWindows) {
          final preview = output
              .replaceAll('\r', '')
              .split('\n')
              .take(12)
              .join(' | ');
          _log(
            'Windows ARP parse produced 0 entries. Output preview: $preview',
          );
        }
      } catch (error) {
        _log('$executable ${args.join(" ")} unavailable: $error');
      }
    }

    return <String, String>{};
  }

  Future<Map<String, String>> _loadArpFromProc({
    String? preferredSourceIp,
  }) async {
    try {
      final file = File('/proc/net/arp');
      if (!await file.exists()) {
        return <String, String>{};
      }
      final lines = await file.readAsLines();
      if (lines.length < 2) {
        return <String, String>{};
      }

      final map = <String, String>{};
      for (var i = 1; i < lines.length; i += 1) {
        final line = lines[i].trim();
        if (line.isEmpty) {
          continue;
        }
        final parts = line.split(RegExp(r'\s+'));
        if (parts.length < 4) {
          continue;
        }
        final ip = parts[0];
        final flags = parts[2];
        final mac = _normalizeMac(parts[3]);
        final valid = flags == '0x2' && mac != null;
        if (!valid) {
          continue;
        }
        if (!_isUsableHostIpv4(ip)) {
          continue;
        }
        if (preferredSourceIp != null &&
            !_isSame24Subnet(ip, preferredSourceIp)) {
          continue;
        }
        map[ip] = mac;
      }
      return map;
    } catch (_) {
      return <String, String>{};
    }
  }

  Map<String, String> _parseArpOutput(
    String output, {
    String? preferredSourceIp,
  }) {
    if (Platform.isWindows) {
      return _parseWindowsArpOutput(
        output,
        preferredSourceIp: preferredSourceIp,
      );
    }

    final entries = <String, String>{};
    final lines = output.split(RegExp(r'\r?\n'));

    final interfaceLine = RegExp(r'(\d+\.\d+\.\d+\.\d+)\s+---');
    final windowsLike = RegExp(
      r'(\d+\.\d+\.\d+\.\d+)\s+([0-9a-fA-F:-]{11,17})\s+(\w+)',
    );
    final genericLike = RegExp(
      r'(\d+\.\d+\.\d+\.\d+).{0,32}([0-9a-fA-F:-]{11,17})',
    );

    String? currentInterfaceIp;
    for (final line in lines) {
      final trimmed = line.trim();
      if (trimmed.isEmpty) {
        continue;
      }

      final interfaceMatch = interfaceLine.firstMatch(trimmed);
      if (interfaceMatch != null) {
        currentInterfaceIp = interfaceMatch.group(1);
        continue;
      }

      final acceptCurrentSection =
          preferredSourceIp == null || currentInterfaceIp == preferredSourceIp;
      if (!acceptCurrentSection) {
        continue;
      }

      final windowsMatch = windowsLike.firstMatch(trimmed);
      if (windowsMatch != null) {
        final ip = windowsMatch.group(1)!;
        final mac = _normalizeMac(windowsMatch.group(2)!);
        final type = windowsMatch.group(3)?.toLowerCase() ?? '';
        if (mac != null &&
            (type.contains('dynamic') || type.contains('static'))) {
          if (!_isUsableHostIpv4(ip)) {
            continue;
          }
          if (preferredSourceIp != null &&
              !_isSame24Subnet(ip, preferredSourceIp)) {
            continue;
          }
          entries[ip] = mac;
          continue;
        }
      }

      final genericMatch = genericLike.firstMatch(trimmed);
      if (genericMatch != null) {
        final ip = genericMatch.group(1)!;
        final mac = _normalizeMac(genericMatch.group(2)!);
        if (mac != null) {
          if (!_isUsableHostIpv4(ip)) {
            continue;
          }
          if (preferredSourceIp != null &&
              !_isSame24Subnet(ip, preferredSourceIp)) {
            continue;
          }
          entries[ip] = mac;
        }
      }
    }

    return entries;
  }

  Map<String, String> _parseWindowsArpOutput(
    String output, {
    String? preferredSourceIp,
  }) {
    final entries = <String, String>{};
    final lines = output.split(RegExp(r'\r?\n'));
    final entry = RegExp(
      r'^\s*(\d+\.\d+\.\d+\.\d+)\s+([0-9a-fA-F]{2}(?:-[0-9a-fA-F]{2}){5}|[0-9a-fA-F]{2}(?::[0-9a-fA-F]{2}){5})\b',
    );

    for (final line in lines) {
      final match = entry.firstMatch(line);
      if (match == null) {
        continue;
      }
      final ip = match.group(1)!;
      final mac = _normalizeMac(match.group(2)!);
      if (mac == null || !_isUsableHostIpv4(ip)) {
        continue;
      }
      if (preferredSourceIp != null &&
          !_isSame24Subnet(ip, preferredSourceIp)) {
        continue;
      }
      entries[ip] = mac;
    }

    return entries;
  }

  String? _normalizeMac(String raw) {
    final lower = raw.toLowerCase().replaceAll('-', ':');
    final valid = RegExp(r'^[0-9a-f]{2}(:[0-9a-f]{2}){5}$').hasMatch(lower);
    if (!valid || lower == '00:00:00:00:00:00') {
      return null;
    }
    return lower;
  }

  Future<Set<String>> _scanWithTcpProbing(
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
        final openPort = await _probeHost(current);
        if (openPort != null) {
          foundHosts.add(current);
          _log('Reachable host: $current (port $openPort)');
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

  Future<int?> _probeHost(String ip) async {
    for (final port in _probePorts) {
      try {
        final socket = await Socket.connect(ip, port, timeout: _probeTimeout);
        socket.destroy();
        return port;
      } on SocketException {
        // Closed/unreachable/timeout: keep probing other ports.
      } catch (_) {
        // Keep probing other ports.
      }
    }

    return null;
  }

  Future<Set<String>> _getLocalIpv4Addresses({
    String? preferredSourceIp,
  }) async {
    final preferredIp = preferredSourceIp?.trim();
    final localIps = <String>{};
    final fallbackIps = <String>{};

    try {
      final interfaces = await NetworkInterface.list(
        type: InternetAddressType.IPv4,
        includeLinkLocal: false,
        includeLoopback: false,
      );
      for (final interface in interfaces) {
        final name = interface.name.toLowerCase();
        final isVirtual = _virtualInterfaceHints.any(name.contains);

        for (final address in interface.addresses) {
          if (isVirtual) {
            fallbackIps.add(address.address);
            continue;
          }
          localIps.add(address.address);
        }
      }
    } catch (error) {
      _log('Failed to enumerate local interfaces: $error');
    }

    if (preferredIp != null && _isValidIpv4(preferredIp)) {
      localIps.add(preferredIp);
      fallbackIps.add(preferredIp);
    }

    final result = localIps.isNotEmpty ? localIps : fallbackIps;
    _log('Interfaces resolved. localIps=$result');
    return result;
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

  bool _isValidIpv4(String ip) {
    final parts = ip.split('.');
    if (parts.length != 4) {
      return false;
    }
    for (final part in parts) {
      final value = int.tryParse(part);
      if (value == null || value < 0 || value > 255) {
        return false;
      }
    }
    return true;
  }

  bool _isUsableHostIpv4(String ip) {
    if (!_isValidIpv4(ip)) {
      return false;
    }

    final parts = ip.split('.');
    final first = int.parse(parts[0]);
    final last = int.parse(parts[3]);
    if (first == 0 || first >= 224 || first == 255) {
      return false;
    }
    if (last == 255) {
      return false;
    }
    return true;
  }

  bool _isSame24Subnet(String ip, String sourceIp) {
    if (!_isValidIpv4(ip) || !_isValidIpv4(sourceIp)) {
      return false;
    }

    final a = ip.split('.');
    final b = sourceIp.split('.');
    return a[0] == b[0] && a[1] == b[1] && a[2] == b[2];
  }

  void _log(String message) {
    developer.log(message, name: 'NetworkHostScanner');
  }
}
