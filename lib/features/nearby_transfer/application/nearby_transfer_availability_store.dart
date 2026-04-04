import 'package:flutter/foundation.dart';

class NearbyTransferAvailabilityStore extends ChangeNotifier {
  int? get lanFallbackPort => _lanFallbackPort;

  bool get isLanFallbackAdvertised => _lanFallbackPort != null;

  int? _lanFallbackPort;

  void advertiseLanFallback(int port) {
    if (_lanFallbackPort == port) {
      return;
    }
    _lanFallbackPort = port;
    notifyListeners();
  }

  void clear() {
    if (_lanFallbackPort == null) {
      return;
    }
    _lanFallbackPort = null;
    notifyListeners();
  }
}
