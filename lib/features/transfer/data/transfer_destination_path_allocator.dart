import 'dart:io';

import 'package:path/path.dart' as p;

class TransferDestinationPathAllocator {
  const TransferDestinationPathAllocator();

  Future<String> allocateDestinationPath({
    required Directory destinationDirectory,
    required String relativePath,
    String? destinationRelativeRootPrefix,
  }) async {
    final sanitizedRelative = sanitizeRelativePath(relativePath);
    final sanitizedPrefix = destinationRelativeRootPrefix == null
        ? null
        : sanitizeRelativePath(destinationRelativeRootPrefix);
    final sanitized = sanitizedPrefix == null || sanitizedPrefix.isEmpty
        ? sanitizedRelative
        : p.join(sanitizedPrefix, sanitizedRelative);
    final fullPath = p.join(destinationDirectory.path, sanitized);
    final file = File(fullPath);
    if (!await file.exists()) {
      return fullPath;
    }

    final dir = p.dirname(fullPath);
    final name = p.basenameWithoutExtension(fullPath);
    final ext = p.extension(fullPath);
    var counter = 1;
    while (true) {
      final candidate = p.join(dir, '$name ($counter)$ext');
      if (!await File(candidate).exists()) {
        return candidate;
      }
      counter += 1;
    }
  }

  Future<String> allocateTemporaryDestinationPath(
    String destinationPath,
  ) async {
    final directory = p.dirname(destinationPath);
    final basename = p.basename(destinationPath);
    var counter = 0;
    while (true) {
      final suffix = counter == 0 ? '' : '.$counter';
      final candidate = p.join(directory, '.$basename.landa-part$suffix');
      if (!await File(candidate).exists() &&
          !await Directory(candidate).exists()) {
        return candidate;
      }
      counter += 1;
    }
  }

  String sanitizeRelativePath(String input) {
    final raw = input.replaceAll('\\', '/');
    final parts = raw
        .split('/')
        .map((part) => _sanitizeRelativePathPart(part.trim()))
        .where((part) => part.isNotEmpty && part != '.' && part != '..')
        .toList(growable: false);
    if (parts.isEmpty) {
      return 'file.bin';
    }
    return p.joinAll(parts);
  }

  String _sanitizeRelativePathPart(String input) {
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

      final reserved = <String>{
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
}
