import 'dart:developer' as developer;

import 'package:flutter/foundation.dart';

import '../data/transfer_history_repository.dart';
import '../domain/transfer_history_record.dart';

class DownloadHistoryBoundary extends ChangeNotifier {
  DownloadHistoryBoundary({
    required TransferHistoryRepository transferHistoryRepository,
    this.limit = 120,
  }) : _transferHistoryRepository = transferHistoryRepository;

  final TransferHistoryRepository _transferHistoryRepository;
  final int limit;
  final List<TransferHistoryRecord> _records = <TransferHistoryRecord>[];

  List<TransferHistoryRecord> get records =>
      List<TransferHistoryRecord>.unmodifiable(_records);

  Future<void> load() async {
    try {
      final rows = await _transferHistoryRepository.listRecords(
        direction: TransferHistoryDirection.download,
        limit: limit,
      );
      _records
        ..clear()
        ..addAll(rows);
      notifyListeners();
    } catch (error) {
      _log('Failed to load download history: $error');
    }
  }

  Future<void> recordDownload({
    required String id,
    String? requestId,
    required String peerName,
    String? peerIp,
    required String rootPath,
    required List<String> savedPaths,
    required int fileCount,
    required int totalBytes,
    required TransferHistoryStatus status,
    required int createdAtMs,
  }) async {
    await _transferHistoryRepository.addRecord(
      id: id,
      requestId: requestId,
      direction: TransferHistoryDirection.download,
      peerName: peerName,
      peerIp: peerIp,
      rootPath: rootPath,
      savedPaths: savedPaths,
      fileCount: fileCount,
      totalBytes: totalBytes,
      status: status,
      createdAtMs: createdAtMs,
    );
    await load();
  }

  void _log(String message) {
    developer.log(message, name: 'DownloadHistoryBoundary');
  }
}
