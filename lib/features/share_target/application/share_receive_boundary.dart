import 'package:flutter/widgets.dart';

import '../data/share_intent_adapter.dart';

class ShareReceiveBoundary extends ChangeNotifier {
  ShareReceiveBoundary({
    Future<List<String>> Function()? consumePendingSharedFiles,
  }) : _consumePendingSharedFiles =
           consumePendingSharedFiles ??
           ShareIntentAdapter().consumePendingSharedFiles;

  final Future<List<String>> Function() _consumePendingSharedFiles;
  final List<String> _pendingFiles = <String>[];
  AppLifecycleListener? _lifecycleListener;
  bool _isConsuming = false;

  bool get hasPendingShare => _pendingFiles.isNotEmpty;

  List<String> get pendingFiles => List<String>.unmodifiable(_pendingFiles);

  Future<void> initialize() => consumePendingShare();

  void startLifecycleListener() {
    _lifecycleListener ??= AppLifecycleListener(
      onResume: () {
        consumePendingShare();
      },
    );
  }

  Future<void> consumePendingShare() async {
    if (_isConsuming) {
      return;
    }
    _isConsuming = true;
    try {
      final paths = await _consumePendingSharedFiles();
      final next = paths
          .map((path) => path.trim())
          .where((path) => path.isNotEmpty)
          .toList(growable: false);
      if (next.isEmpty) {
        return;
      }
      _pendingFiles
        ..clear()
        ..addAll(next);
      notifyListeners();
    } finally {
      _isConsuming = false;
    }
  }

  void clearPendingShare() {
    if (_pendingFiles.isEmpty) {
      return;
    }
    _pendingFiles.clear();
    notifyListeners();
  }

  @override
  void dispose() {
    _lifecycleListener?.dispose();
    super.dispose();
  }
}
