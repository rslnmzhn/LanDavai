import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

void main() {
  final sourceTree = _SourceTree(repoRoot: Directory.current.path);

  group('God-service refactor regression guards', () {
    test('keeps PR-cycle hotspot baseline explicit', () {
      const hotspotFiles = <String>[
        'lib/features/discovery/application/discovery_controller.dart',
        'lib/features/transfer/application/shared_download_boundary.dart',
        'lib/features/files/application/preview_cache_owner.dart',
        'lib/features/transfer/data/file_transfer_service.dart',
        'lib/features/discovery/data/lan_discovery_service.dart',
        'lib/features/nearby_transfer/data/lan_nearby_transport_adapter.dart',
      ];

      for (final path in hotspotFiles) {
        expect(
          sourceTree.fileExists(path),
          isTrue,
          reason:
              '$path is part of the PR-cycle hotspot baseline. If a planned extraction renames or removes it, update this guard and docs/PR_Cycle.md in the same PR.',
        );
      }
    });

    test('keeps raw interface enumeration inside the discovery data catalog', () {
      const allowedPath =
          'lib/features/discovery/data/discovery_network_interface_catalog.dart';

      final matches = sourceTree.findLiteralInLib('NetworkInterface.list(');
      final invalidMatches = matches
          .where((match) => match.path != allowedPath)
          .toList(growable: false);

      expect(
        invalidMatches,
        isEmpty,
        reason: sourceTree.describeMatches(
          label: 'NetworkInterface.list outside $allowedPath',
          matches: invalidMatches,
          why:
              'Raw interface enumeration belongs in the discovery data catalog. Consumers must use owner-provided local source IPs instead of re-enumerating interfaces.',
        ),
      );
      expect(
        sourceTree.fileContainsLiteral(allowedPath, 'NetworkInterface.list('),
        isTrue,
        reason:
            '$allowedPath is the current explicit data-catalog seam for raw interface enumeration. If this moves, update the guard with the replacement catalog seam.',
      );
    });

    test('keeps subnet grouping and scope selection outside DiscoveryController', () {
      const controllerPath =
          'lib/features/discovery/application/discovery_controller.dart';

      for (final pattern in <RegExp>[
        RegExp(
          r'''^import\s+['"].*discovery_network_scope_grouper\.dart['"];''',
          multiLine: true,
        ),
        RegExp(
          r'''^import\s+['"].*discovery_network_interface_catalog\.dart['"];''',
          multiLine: true,
        ),
      ]) {
        expect(
          sourceTree.fileContainsRegex(controllerPath, pattern),
          isFalse,
          reason:
              '$controllerPath must not import network interface catalog/grouper seams; DiscoveryNetworkScopeStore owns grouped scope truth.',
        );
      }

      for (final symbol in <String>[
        'NetworkInterface.list(',
        'DiscoveryNetworkScopeGrouper',
        'DiscoveryRawNetworkInterface',
        'DiscoveryNetworkInterfaceCatalog',
        'subnetCidrForIp(',
        'rangeIdForSubnet(',
        '_groupedNetworkScopes',
        '_selectedNetworkScopeId',
      ]) {
        expect(
          sourceTree.fileContainsLiteral(controllerPath, symbol),
          isFalse,
          reason:
              '$controllerPath must not regain network-scope ownership or grouping residue "$symbol".',
        );
      }
    });

    test('keeps discovery transports on provided local source IP seams', () {
      const transportPath =
          'lib/features/discovery/data/discovery_transport_adapter.dart';
      const scannerPath =
          'lib/features/discovery/data/network_host_scanner.dart';

      for (final path in <String>[transportPath, scannerPath]) {
        expect(
          sourceTree.fileContainsRegex(
            path,
            RegExp(r'Set<String>\s+localSourceIps\b'),
          ),
          isTrue,
          reason:
              '$path must keep a stable seam that consumes active localSourceIps from DiscoveryNetworkScopeStore-owned selection.',
        );
        expect(
          sourceTree.fileContainsLiteral(path, 'NetworkInterface.list('),
          isFalse,
          reason:
              '$path must not re-enumerate local interfaces; it must use the provided active local source IPs.',
        );
      }
    });

    test('keeps LanDiscoveryService on coordinator-only discovery seams', () {
      const servicePath =
          'lib/features/discovery/data/lan_discovery_service.dart';
      const requiredHelpers = <String>[
        'lib/features/discovery/data/lan_presence_announcement_sender.dart',
        'lib/features/discovery/data/lan_discovery_target_registry.dart',
        'lib/features/discovery/data/lan_transfer_packet_sender.dart',
        'lib/features/discovery/data/lan_friend_packet_sender.dart',
        'lib/features/discovery/data/lan_share_packet_sender.dart',
        'lib/features/discovery/data/lan_clipboard_packet_sender.dart',
        'lib/features/discovery/data/lan_share_catalog_chunk_encoder.dart',
        'lib/features/discovery/data/lan_clipboard_catalog_packet_fitter.dart',
        'lib/features/discovery/data/lan_incoming_datagram_admission.dart',
        'lib/features/discovery/data/lan_discovery_session_callbacks.dart',
        'lib/features/discovery/data/lan_discovery_lifecycle_state.dart',
      ];

      for (final path in requiredHelpers) {
        expect(
          sourceTree.fileExists(path),
          isTrue,
          reason:
              '$path is a durable LanDiscoveryService extraction seam from the PR cycle and must not disappear without updating the cycle guards.',
        );
      }

      for (final literal in <String>[
        'Timer? _beaconTimer',
        'bool _started =',
        '_internetPeers',
        '_internetPeerIpAllowlist',
        '_configuredTargetIps',
        '_sendOutgoingPacket',
        '_sendOutgoingPackets',
        'decodeIncomingPacket(',
        'encodeTransferRequest(',
        'encodeTransferDecision(',
        'encodeFriendRequest(',
        'encodeFriendResponse(',
        'encodeShareCatalogChunks(',
        'fitClipboardCatalogEntries(',
        'encodeClipboardCatalog(',
      ]) {
        expect(
          sourceTree.fileContainsLiteral(servicePath, literal),
          isFalse,
          reason:
              '$servicePath must remain a lifecycle/public-API coordinator and must not regain extracted responsibility "$literal".',
        );
      }

      expect(
        sourceTree.fileContainsRegex(
          servicePath,
          RegExp(r'\bpacket\s+is\s+Lan[A-Za-z]+Packet\b'),
        ),
        isFalse,
        reason:
            '$servicePath must not regain incoming packet type dispatch; LanIncomingPacketDispatcher owns packet branching.',
      );
    });

    test('keeps lifecycle helper away from UDP transport ownership', () {
      const servicePath =
          'lib/features/discovery/data/lan_discovery_service.dart';
      const lifecyclePath =
          'lib/features/discovery/data/lan_discovery_lifecycle_state.dart';

      expect(
        sourceTree.fileContainsLiteral(servicePath, '_transportAdapter.start('),
        isTrue,
        reason:
            '$servicePath must keep direct DiscoveryTransportAdapter.start ownership.',
      );
      expect(
        sourceTree.fileContainsLiteral(servicePath, '_transportAdapter.stop()'),
        isTrue,
        reason:
            '$servicePath must keep direct DiscoveryTransportAdapter.stop ownership.',
      );

      for (final literal in <String>[
        'DiscoveryTransportAdapter',
        'transportAdapter',
        'startTransport',
        'stopTransport',
        '.start(',
        '.stop(',
        'send(',
        'NetworkInterface.list(',
      ]) {
        expect(
          sourceTree.fileContainsLiteral(lifecyclePath, literal),
          isFalse,
          reason:
              '$lifecyclePath may own lifecycle state only; it must not own UDP transport lifecycle or packet sending residue "$literal".',
        );
      }
    });

    test('keeps extracted LAN discovery helpers under the file size limit', () {
      const extractedHelpers = <String>[
        'lib/features/discovery/data/lan_presence_announcement_sender.dart',
        'lib/features/discovery/data/lan_discovery_target_registry.dart',
        'lib/features/discovery/data/lan_transfer_packet_sender.dart',
        'lib/features/discovery/data/lan_friend_packet_sender.dart',
        'lib/features/discovery/data/lan_share_packet_sender.dart',
        'lib/features/discovery/data/lan_clipboard_packet_sender.dart',
        'lib/features/discovery/data/lan_share_catalog_chunk_encoder.dart',
        'lib/features/discovery/data/lan_clipboard_catalog_packet_fitter.dart',
        'lib/features/discovery/data/lan_incoming_datagram_admission.dart',
        'lib/features/discovery/data/lan_discovery_session_callbacks.dart',
        'lib/features/discovery/data/lan_discovery_lifecycle_state.dart',
      ];
      final oversizedHelpers = <String>[];
      for (final path in extractedHelpers) {
        final lineCount = sourceTree.fileLineCount(path);
        if (lineCount > 500) {
          oversizedHelpers.add('$path ($lineCount lines)');
        }
      }

      expect(
        oversizedHelpers,
        isEmpty,
        reason:
            'Extracted LAN discovery helper files must stay below 500 lines. Oversized files: ${oversizedHelpers.join(', ')}',
      );
    });
  });
}

class _SourceTree {
  _SourceTree({required this.repoRoot})
    : _libRoot = p.join(repoRoot, 'lib'),
      _libFiles = _loadLibFiles(p.join(repoRoot, 'lib'));

  final String repoRoot;
  final String _libRoot;
  final Map<String, String> _libFiles;

  static Map<String, String> _loadLibFiles(String libRoot) {
    final root = Directory(libRoot);
    if (!root.existsSync()) {
      throw StateError('Cannot find lib/ under ${Directory.current.path}.');
    }

    final files = <String, String>{};
    for (final entity in root.listSync(recursive: true)) {
      if (entity is! File || !entity.path.endsWith('.dart')) {
        continue;
      }
      final normalizedPath = p
          .relative(entity.path, from: Directory.current.path)
          .replaceAll('\\', '/');
      files[normalizedPath] = entity.readAsStringSync();
    }
    return files;
  }

  bool fileExists(String relativePath) {
    return _libFiles.containsKey(relativePath);
  }

  bool fileContainsLiteral(String relativePath, String literal) {
    return _readFile(relativePath).contains(literal);
  }

  bool fileContainsRegex(String relativePath, RegExp pattern) {
    return pattern.hasMatch(_readFile(relativePath));
  }

  int fileLineCount(String relativePath) {
    final text = _readFile(relativePath);
    if (text.isEmpty) {
      return 0;
    }
    return text.split('\n').length;
  }

  List<_SourceMatch> findLiteralInLib(String literal) {
    final matches = <_SourceMatch>[];
    for (final entry in _libFiles.entries) {
      if (!entry.value.contains(literal)) {
        continue;
      }
      matches.add(_SourceMatch(path: entry.key, snippet: literal));
    }
    return matches;
  }

  String describeMatches({
    required String label,
    required List<_SourceMatch> matches,
    required String why,
  }) {
    if (matches.isEmpty) {
      return '$label was not found.';
    }

    final lines = <String>[
      'Forbidden residue found for $label.',
      why,
      'Matches under ${p.relative(_libRoot, from: repoRoot).replaceAll("\\", "/")}:',
      ...matches.map((match) => '- ${match.path}: ${match.snippet}'),
    ];
    return lines.join('\n');
  }

  String _readFile(String relativePath) {
    final text = _libFiles[relativePath];
    if (text == null) {
      throw StateError('Missing expected source file: $relativePath');
    }
    return text;
  }
}

class _SourceMatch {
  const _SourceMatch({required this.path, required this.snippet});

  final String path;
  final String snippet;
}
