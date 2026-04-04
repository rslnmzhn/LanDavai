import 'dart:io';

import 'package:path/path.dart' as p;

import '../../transfer/data/transfer_storage_service.dart';

class NearbyTransferStorageService {
  const NearbyTransferStorageService({
    required TransferStorageService transferStorageService,
  }) : _transferStorageService = transferStorageService;

  final TransferStorageService _transferStorageService;

  Future<Directory> resolveReceiveDirectory() {
    return _transferStorageService.resolveReceiveDirectory();
  }

  Future<String> allocateDestinationPath({
    required Directory destinationDirectory,
    required String relativePath,
  }) async {
    final sanitized = _sanitizeRelativePath(relativePath);
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

  String _sanitizeRelativePath(String input) {
    final normalized = input.replaceAll('\\', '/');
    final parts = normalized
        .split('/')
        .map((part) => _sanitizePart(part.trim()))
        .where((part) => part.isNotEmpty && part != '.' && part != '..')
        .toList(growable: false);
    if (parts.isEmpty) {
      return 'file.bin';
    }
    return p.joinAll(parts);
  }

  String _sanitizePart(String input) {
    if (input.isEmpty) {
      return '';
    }

    var value = input
        .replaceAll(RegExp(r'[\x00-\x1F]'), '')
        .replaceAll(RegExp(r'[<>:"/\\|?*]'), '_');
    if (Platform.isWindows) {
      value = value.trimRight().replaceFirst(RegExp(r'[. ]+$'), '');
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
}
