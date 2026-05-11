import 'dart:io';

class IncomingTransferCompletionPathVerifier {
  const IncomingTransferCompletionPathVerifier();

  Future<List<String>> verifyReceivedSavedPaths(List<String> paths) async {
    if (paths.isEmpty) {
      throw StateError('Transfer completed without saved files.');
    }
    final verified = <String>[];
    for (final path in paths) {
      final trimmed = path.trim();
      if (trimmed.isEmpty) {
        throw StateError('Transfer completed with an empty saved file path.');
      }
      final file = File(trimmed);
      if (!await file.exists()) {
        throw StateError('Received file is missing on disk: $trimmed');
      }
      final stat = await file.stat();
      if (stat.type != FileSystemEntityType.file) {
        throw StateError('Received path is not a file: $trimmed');
      }
      verified.add(trimmed);
    }
    return List<String>.unmodifiable(verified);
  }
}
