import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

void main() {
  final sourceTree = _SourceTree(repoRoot: Directory.current.path);

  group('Architecture guards', () {
    test('forbids shared-cache bridge and callback backchannel residue', () {
      expect(
        sourceTree.findLiteralInLib('SharedCacheCatalogBridge'),
        isEmpty,
        reason: sourceTree.describeMatches(
          label: 'SharedCacheCatalogBridge',
          matches: sourceTree.findLiteralInLib('SharedCacheCatalogBridge'),
          why:
              'SharedCacheCatalogBridge was deleted by workpack 04 and must not return on production paths.',
        ),
      );

      for (final symbol in <String>[
        'onRecacheSharedFolders',
        'onRemoveSharedCache',
        'recacheStateListenable',
      ]) {
        final matches = sourceTree.findLiteralInLib(symbol);
        expect(
          matches,
          isEmpty,
          reason: sourceTree.describeMatches(
            label: symbol,
            matches: matches,
            why:
                'The files/shared-cache callback backchannel was deleted by workpack 04 and must not be reintroduced.',
          ),
        );
      }
    });

    test('forbids part directives under lib', () {
      final directiveMatches = sourceTree.findRegexInLib(
        RegExp(r'''^\s*part\s+['"]|^\s*part\s+of\b''', multiLine: true),
      );
      expect(
        directiveMatches,
        isEmpty,
        reason: sourceTree.describeMatches(
          label: 'part / part of',
          matches: directiveMatches,
          why:
              'Critical seams under lib/ must stay on explicit imports only; part-based regressions are forbidden.',
        ),
      );
    });

    test('keeps local peer identity on LocalPeerIdentityStore', () {
      const controllerPath =
          'lib/features/discovery/application/discovery_controller.dart';
      const friendRepositoryPath =
          'lib/features/discovery/data/friend_repository.dart';
      const localPeerIdentityStorePath =
          'lib/features/discovery/application/local_peer_identity_store.dart';

      expect(
        sourceTree.fileContainsRegex(
          controllerPath,
          RegExp(
            r'''^import\s+['"].*friend_repository\.dart['"];''',
            multiLine: true,
          ),
        ),
        isFalse,
        reason:
            '$controllerPath must not import friend_repository.dart; workpack 01 moved local peer identity ownership out of FriendRepository.',
      );
      expect(
        sourceTree.fileContainsLiteral(
          friendRepositoryPath,
          'loadOrCreateLocalPeerId(',
        ),
        isFalse,
        reason:
            '$friendRepositoryPath must stay friend-only and must not re-declare local peer identity loading.',
      );
      expect(
        sourceTree.fileContainsLiteral(friendRepositoryPath, 'local_peer_id'),
        isFalse,
        reason:
            '$friendRepositoryPath must not own the local_peer_id setting key anymore.',
      );

      final declarationMatches = sourceTree.findRegexInLib(
        RegExp(
          r'^\s*(?:static\s+)?(?:Future<[^>]+>|[A-Za-z_][\w<>,? ]*)\s+loadOrCreateLocalPeerId\s*\(',
          multiLine: true,
        ),
      );
      final invalidMatches = declarationMatches
          .where((match) => match.path != localPeerIdentityStorePath)
          .toList(growable: false);
      expect(
        invalidMatches,
        isEmpty,
        reason: sourceTree.describeMatches(
          label: 'loadOrCreateLocalPeerId declaration',
          matches: invalidMatches,
          why:
              'Only LocalPeerIdentityStore may declare/implement loadOrCreateLocalPeerId(). Calls through DiscoveryController are allowed; new declarations are not.',
        ),
      );
    });

    test(
      'keeps DiscoveryController away from remote-share thumbnail IO and video-link mirror residue',
      () {
        const controllerPath =
            'lib/features/discovery/application/discovery_controller.dart';

        for (final literal in <String>[
          'readOwnerThumbnailBytes(',
          'resolveReceiverThumbnailPath(',
          'saveReceiverThumbnailBytes(',
          '_videoLinkShareSession',
          'videoLinkWatchUrl',
          'publishVideoLinkShare(',
          'stopVideoLinkShare(',
        ]) {
          expect(
            sourceTree.fileContainsLiteral(controllerPath, literal),
            isFalse,
            reason:
                '$controllerPath contains forbidden residue "$literal". Remote-share media IO and video-link session truth must stay outside DiscoveryController.',
          );
        }

        for (final pattern in <RegExp>[
          RegExp(
            r'''^import\s+['"].*thumbnail_cache_service\.dart['"];''',
            multiLine: true,
          ),
          RegExp(
            r'''^import\s+['"].*shared_folder_cache_repository\.dart['"];''',
            multiLine: true,
          ),
        ]) {
          expect(
            sourceTree.fileContainsRegex(controllerPath, pattern),
            isFalse,
            reason:
                '$controllerPath imports a forbidden infra collaborator. Workpacks 06, 07, and 08 moved those seams behind explicit boundaries.',
          );
        }
      },
    );

    test('keeps SharedCacheCatalog on SharedCacheRecordStore only', () {
      const catalogPath =
          'lib/features/transfer/application/shared_cache_catalog.dart';

      expect(
        sourceTree.fileContainsRegex(
          catalogPath,
          RegExp(
            r'''^import\s+['"].*shared_folder_cache_repository\.dart['"];''',
            multiLine: true,
          ),
        ),
        isFalse,
        reason:
            '$catalogPath must not import shared_folder_cache_repository.dart directly; workpack 07 reduced the coupling to SharedCacheRecordStore.',
      );
      expect(
        sourceTree.fileContainsLiteral(
          catalogPath,
          "import '../data/shared_cache_record_store.dart';",
        ),
        isTrue,
        reason:
            '$catalogPath must import shared_cache_record_store.dart as its row-persistence contract.',
      );
      expect(
        sourceTree.fileContainsLiteral(
          catalogPath,
          'required SharedCacheRecordStore sharedCacheRecordStore,',
        ),
        isTrue,
        reason:
            '$catalogPath must keep SharedCacheRecordStore in its constructor contract.',
      );
      expect(
        sourceTree.fileContainsLiteral(
          catalogPath,
          'final SharedCacheRecordStore _sharedCacheRecordStore;',
        ),
        isTrue,
        reason:
            '$catalogPath must keep SharedCacheRecordStore as its stored collaborator, not a concrete repository type.',
      );
    });

    test('keeps SharedFolderCacheRepository thin', () {
      const repositoryPath =
          'lib/features/transfer/data/shared_folder_cache_repository.dart';

      for (final literal in <String>[
        'buildOwnerCache(',
        'upsertOwnerFolderCache(',
        'buildOwnerSelectionCache(',
        'saveReceiverCache(',
        'refreshOwnerSelectionCacheEntries(',
        'refreshOwnerFolderSubdirectoryEntries(',
        'deleteCache(',
        'pruneUnavailableOwnerCaches(',
        'pruneReceiverCachesForOwner(',
      ]) {
        expect(
          sourceTree.fileContainsLiteral(repositoryPath, literal),
          isFalse,
          reason:
              '$repositoryPath contains forbidden broad-repository residue "$literal". Workpack 07 reduced this file to row-level persistence only.',
        );
      }
    });

    test('keeps lan_packet_codec_common free of DTOs and family logic', () {
      const commonPath =
          'lib/features/discovery/data/lan_packet_codec_common.dart';

      expect(
        sourceTree.findRegexInFile(
          commonPath,
          RegExp(
            r'^\s*(?:abstract\s+)?class\s+\w+(?:Packet|Item)\b',
            multiLine: true,
          ),
        ),
        isEmpty,
        reason:
            '$commonPath must not become a DTO source; packet/item classes belong in lan_packet_codec_models.dart.',
      );

      final familyMethodMatches = sourceTree.findRegexInFile(
        commonPath,
        RegExp(
          r'^\s*(?:static\s+)?(?:[\w<>,? \[\]]+\s+)?(?:parse[A-Za-z]+Packet|encodeTransfer\w*|encodeFriend\w*|encodeShare\w*|encodeThumbnail\w*|encodeClipboard\w*|fitShareCatalogEntries)\s*\(',
          multiLine: true,
        ),
      );
      expect(
        familyMethodMatches,
        isEmpty,
        reason: sourceTree.describeMatches(
          label:
              'family-specific protocol logic in lan_packet_codec_common.dart',
          matches: familyMethodMatches,
          why:
              'lan_packet_codec_common.dart must stay limited to shared constants and envelope helpers; family logic belongs in dedicated codec files.',
        ),
      );
    });

    test(
      'keeps protocol-internal files on direct common/models imports instead of the facade shell',
      () {
        const protocolInternalFiles = <String>[
          'lib/features/discovery/data/lan_presence_protocol_handler.dart',
          'lib/features/discovery/data/lan_transfer_protocol_handler.dart',
          'lib/features/discovery/data/lan_friend_protocol_handler.dart',
          'lib/features/discovery/data/lan_share_protocol_handler.dart',
          'lib/features/discovery/data/lan_clipboard_protocol_handler.dart',
          'lib/features/discovery/data/lan_protocol_events.dart',
          'lib/features/discovery/data/lan_presence_packet_codec.dart',
          'lib/features/discovery/data/lan_transfer_packet_codec.dart',
          'lib/features/discovery/data/lan_friend_packet_codec.dart',
          'lib/features/discovery/data/lan_share_packet_codec.dart',
          'lib/features/discovery/data/lan_clipboard_packet_codec.dart',
        ];

        final matches = <_SourceMatch>[];
        final facadeImport = RegExp(
          r'''^import\s+['"].*lan_packet_codec\.dart['"](?:\s+show\s+.+)?;''',
          multiLine: true,
        );
        for (final path in protocolInternalFiles) {
          matches.addAll(sourceTree.findRegexInFile(path, facadeImport));
        }

        expect(
          matches,
          isEmpty,
          reason: sourceTree.describeMatches(
            label: 'protocol-internal lan_packet_codec.dart import',
            matches: matches,
            why:
                'Protocol-internal files must read DTO/constant truth directly from lan_packet_codec_models.dart and lan_packet_codec_common.dart. The facade shell is allowed for runtime consumers, not for internal protocol truth routing.',
          ),
        );
      },
    );
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

  List<_SourceMatch> findRegexInLib(RegExp pattern) {
    final matches = <_SourceMatch>[];
    for (final path in _libFiles.keys) {
      matches.addAll(findRegexInFile(path, pattern));
    }
    return matches;
  }

  List<_SourceMatch> findRegexInFile(String relativePath, RegExp pattern) {
    final text = _readFile(relativePath);
    return pattern
        .allMatches(text)
        .map(
          (match) => _SourceMatch(
            path: relativePath,
            snippet: _snippet(text, match.start, match.end),
          ),
        )
        .toList(growable: false);
  }

  bool fileContainsLiteral(String relativePath, String literal) {
    return _readFile(relativePath).contains(literal);
  }

  bool fileContainsRegex(String relativePath, RegExp pattern) {
    return pattern.hasMatch(_readFile(relativePath));
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
      'Matches under ${p.relative(_libRoot, from: repoRoot).replaceAll("\\\\", "/")}:',
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

  String _snippet(String text, int start, int end) {
    final safeStart = start < 0 ? 0 : start;
    final safeEnd = end > text.length ? text.length : end;
    final lineStart = text.lastIndexOf(
      '\n',
      safeStart == 0 ? 0 : safeStart - 1,
    );
    final lineEnd = text.indexOf('\n', safeEnd);
    final snippet = text.substring(
      lineStart == -1 ? 0 : lineStart + 1,
      lineEnd == -1 ? text.length : lineEnd,
    );
    return snippet.trim();
  }
}

class _SourceMatch {
  const _SourceMatch({required this.path, required this.snippet});

  final String path;
  final String snippet;
}
