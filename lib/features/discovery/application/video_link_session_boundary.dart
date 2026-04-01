import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';

import '../../transfer/data/video_link_share_service.dart';

class VideoLinkSessionBoundaryException implements Exception {
  const VideoLinkSessionBoundaryException(this.message);

  final String message;

  @override
  String toString() => message;
}

class VideoLinkSessionBoundary extends ChangeNotifier {
  VideoLinkSessionBoundary({
    required VideoLinkShareService videoLinkShareService,
    required String? Function() hostAddressProvider,
    Listenable? hostChangeListenable,
    bool disposeService = true,
  }) : _videoLinkShareService = videoLinkShareService,
       _hostAddressProvider = hostAddressProvider,
       _hostChangeListenable = hostChangeListenable,
       _disposeService = disposeService {
    _hostChangeListenable?.addListener(_handleHostChanged);
  }

  final VideoLinkShareService _videoLinkShareService;
  final String? Function() _hostAddressProvider;
  final Listenable? _hostChangeListenable;
  final bool _disposeService;

  VideoLinkShareSession? get activeSession =>
      _videoLinkShareService.activeSession;

  String? get watchUrl {
    final session = activeSession;
    if (session == null) {
      return null;
    }
    final host = _hostAddressProvider()?.trim();
    final safeHost = host == null || host.isEmpty
        ? InternetAddress.loopbackIPv4.address
        : host;
    return session.buildWatchUrl(hostAddress: safeHost);
  }

  Future<String?> publishVideoLinkShare({
    required String filePath,
    required String displayName,
    required String password,
  }) async {
    final normalizedPassword = password.trim();
    if (normalizedPassword.isEmpty) {
      throw const VideoLinkSessionBoundaryException(
        'Password is required for video link sharing.',
      );
    }
    await _videoLinkShareService.publish(
      filePath: filePath,
      displayName: displayName,
      password: normalizedPassword,
    );
    notifyListeners();
    return watchUrl;
  }

  Future<void> stopVideoLinkShare() async {
    await _videoLinkShareService.stop();
    notifyListeners();
  }

  void _handleHostChanged() {
    if (activeSession == null) {
      return;
    }
    notifyListeners();
  }

  @override
  void dispose() {
    _hostChangeListenable?.removeListener(_handleHostChanged);
    if (_disposeService) {
      unawaited(_videoLinkShareService.stop());
    }
    super.dispose();
  }
}
