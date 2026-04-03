import 'package:flutter/foundation.dart';

class ClipboardSourceScopeStore extends ChangeNotifier {
  static const String localSourceId = 'clipboard-source:local';
  static const String _remotePrefix = 'clipboard-source:remote:';

  String _selectedSourceId = localSourceId;

  String get selectedSourceId => _selectedSourceId;

  bool get isLocalSelected => _selectedSourceId == localSourceId;

  String? get selectedRemoteIp {
    if (isLocalSelected || !_selectedSourceId.startsWith(_remotePrefix)) {
      return null;
    }
    return _selectedSourceId.substring(_remotePrefix.length);
  }

  void selectLocal() {
    if (_selectedSourceId == localSourceId) {
      return;
    }
    _selectedSourceId = localSourceId;
    notifyListeners();
  }

  void selectRemote(String ownerIp) {
    final normalizedIp = ownerIp.trim();
    if (normalizedIp.isEmpty) {
      selectLocal();
      return;
    }

    final nextSourceId = remoteSourceId(normalizedIp);
    if (_selectedSourceId == nextSourceId) {
      return;
    }
    _selectedSourceId = nextSourceId;
    notifyListeners();
  }

  void syncAvailableRemoteIps(Iterable<String> ownerIps) {
    final selectedIp = selectedRemoteIp;
    if (selectedIp == null) {
      return;
    }

    final normalizedIps = ownerIps
        .map((value) => value.trim())
        .where((value) => value.isNotEmpty)
        .toSet();
    if (normalizedIps.contains(selectedIp)) {
      return;
    }

    _selectedSourceId = localSourceId;
    notifyListeners();
  }

  static String remoteSourceId(String ownerIp) {
    return '$_remotePrefix${ownerIp.trim()}';
  }
}
