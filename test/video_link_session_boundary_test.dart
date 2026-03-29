import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:landa/features/discovery/application/video_link_session_boundary.dart';
import 'package:landa/features/transfer/data/video_link_share_service.dart';

void main() {
  late VideoLinkShareService service;
  late VideoLinkSessionBoundary boundary;
  late ValueNotifier<String?> hostAddress;
  late Directory tempDir;

  setUp(() async {
    service = VideoLinkShareService();
    hostAddress = ValueNotifier<String?>('192.168.1.20');
    boundary = VideoLinkSessionBoundary(
      videoLinkShareService: service,
      hostAddressProvider: () => hostAddress.value,
      hostChangeListenable: hostAddress,
    );
    tempDir = await Directory.systemTemp.createTemp(
      'landa_video_link_boundary_',
    );
  });

  tearDown(() async {
    boundary.dispose();
    hostAddress.dispose();
    if (await tempDir.exists()) {
      await tempDir.delete(recursive: true);
    }
  });

  test(
    'publishes and clears video-link session through boundary only',
    () async {
      final file = File('${tempDir.path}\\sample.mp4');
      await file.writeAsBytes(<int>[1, 2, 3, 4], flush: true);

      final watchUrl = await boundary.publishVideoLinkShare(
        filePath: file.path,
        displayName: 'sample.mp4',
        password: 'secret-pass',
      );

      expect(boundary.activeSession, isNotNull);
      expect(boundary.activeSession?.fileName, 'sample.mp4');
      expect(watchUrl, contains('192.168.1.20'));
      expect(boundary.watchUrl, watchUrl);

      hostAddress.value = '192.168.1.21';
      expect(boundary.watchUrl, contains('192.168.1.21'));

      await boundary.stopVideoLinkShare();

      expect(boundary.activeSession, isNull);
      expect(boundary.watchUrl, isNull);
    },
  );
}
