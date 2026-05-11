import 'dart:io';

import 'package:path/path.dart' as p;

class TransferPathPolicy {
  const TransferPathPolicy();

  String sanitizeRelativePath(String input) {
    final raw = input.replaceAll('\\', '/');
    final parts = raw
        .split('/')
        .map((part) => sanitizeRelativePathPart(part.trim()))
        .where((part) => part.isNotEmpty && part != '.' && part != '..')
        .toList(growable: false);
    if (parts.isEmpty) {
      return 'file.bin';
    }
    return p.joinAll(parts);
  }

  String sanitizeRelativePathPart(String input) {
    if (input.isEmpty) {
      return '';
    }

    var value = input
        .replaceAll(RegExp(r'[\x00-\x1F]'), '')
        .replaceAll(RegExp(r'[<>:"/\\|?*]'), '_');

    if (Platform.isWindows) {
      value = value.trimRight();
      value = value.replaceFirst(RegExp(r'[. ]+$'), '');
      if (value.isEmpty) {
        return '_';
      }

      const reserved = <String>{
        'con',
        'prn',
        'aux',
        'nul',
        'com1',
        'com2',
        'com3',
        'com4',
        'com5',
        'com6',
        'com7',
        'com8',
        'com9',
        'lpt1',
        'lpt2',
        'lpt3',
        'lpt4',
        'lpt5',
        'lpt6',
        'lpt7',
        'lpt8',
        'lpt9',
      };
      final base = value.split('.').first.toLowerCase();
      if (reserved.contains(base)) {
        value = '_$value';
      }
    }

    if (value.length > 120) {
      value = value.substring(0, 120);
    }

    return value.isEmpty ? '_' : value;
  }

  String buildReceiveRelativePath(
    String relativePath, {
    String? destinationRelativeRootPrefix,
  }) {
    final sanitizedRelativePath = sanitizeRelativePath(relativePath);
    final sanitizedPrefix = destinationRelativeRootPrefix?.trim();
    if (sanitizedPrefix == null || sanitizedPrefix.isEmpty) {
      return sanitizedRelativePath;
    }
    return p.join(sanitizedPrefix, sanitizedRelativePath);
  }

  String? resolveReceiveRootPrefix(String sharedLabel) {
    final sanitized = sanitizeRelativePathPart(sharedLabel.trim());
    if (sanitized.isEmpty || sanitized == '_') {
      return null;
    }
    return sanitized;
  }

  String sharedParentPath(List<String> paths) {
    if (paths.isEmpty) {
      return '';
    }

    final directories = paths
        .map((path) => p.normalize(p.dirname(path)))
        .where((path) => path.isNotEmpty)
        .toList(growable: false);
    if (directories.isEmpty) {
      return '';
    }

    var common = p.split(directories.first);
    for (final directory in directories.skip(1)) {
      final next = p.split(directory);
      var sharedLength = 0;
      while (sharedLength < common.length &&
          sharedLength < next.length &&
          common[sharedLength] == next[sharedLength]) {
        sharedLength += 1;
      }
      common = common.take(sharedLength).toList(growable: false);
      if (common.isEmpty) {
        break;
      }
    }
    if (common.isEmpty) {
      final rootPrefix = p.rootPrefix(paths.first);
      return rootPrefix.isEmpty ? p.dirname(paths.first) : rootPrefix;
    }
    return p.joinAll(common);
  }

  String normalizeForMatch(String value) {
    return value.replaceAll('\\', '/').trim().toLowerCase();
  }
}
