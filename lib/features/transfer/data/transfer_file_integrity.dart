import 'dart:io';

class TransferFileIntegrity {
  const TransferFileIntegrity();

  Future<void> verifyCompletedFile({
    required String path,
    required int expectedBytes,
    required String label,
  }) async {
    final file = File(path);
    if (!await file.exists()) {
      throw StateError('Received file was not written: $label');
    }
    final stat = await file.stat();
    if (stat.type != FileSystemEntityType.file) {
      throw StateError('Received path is not a file: $label');
    }
    if (stat.size != expectedBytes) {
      throw StateError(
        'Received file size mismatch for $label '
        '(expected $expectedBytes, got ${stat.size}).',
      );
    }
  }
}
