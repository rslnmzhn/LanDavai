import 'dart:async';
import 'dart:developer' as developer;

import 'package:flutter/widgets.dart';

import '../data/share_intent_adapter.dart';

class ShareReceiveBoundary extends ChangeNotifier {
  ShareReceiveBoundary({
    Future<List<String>> Function()? consumePendingSharedFiles,
    Future<int> Function(List<String> paths)? discardConsumedFiles,
  }) : _consumePendingSharedFiles =
           consumePendingSharedFiles ??
           ShareIntentAdapter().consumePendingSharedFiles,
       _discardConsumedFiles =
           discardConsumedFiles ??
           ShareIntentAdapter().discardPendingSharedFiles;

  final Future<List<String>> Function() _consumePendingSharedFiles;
  final Future<int> Function(List<String> paths) _discardConsumedFiles;
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

  /// Drops the pending share and best-effort deletes the consumed staging
  /// copies (share-intent files live in the app cache until this point).
  /// Runs both on successful send and on explicit user discard.
  void clearPendingShare() {
    if (_pendingFiles.isEmpty) {
      return;
    }
    final stalePaths = List<String>.of(_pendingFiles);
    _pendingFiles.clear();
    notifyListeners();
    unawaited(_discardQuietly(stalePaths));
  }

  /// try/catch instead of Future.catchError: injected discarders may be
  /// typed with a narrower (e.g. Never) future type at runtime.
  Future<void> _discardQuietly(List<String> paths) async {
    try {
      await _discardConsumedFiles(paths);
    } catch (error) {
      developer.log(
        'Failed to discard consumed share intent files: $error',
        name: 'ShareReceiveBoundary',
      );
    }
  }

  @override
  void dispose() {
    _lifecycleListener?.dispose();
    super.dispose();
  }
}
