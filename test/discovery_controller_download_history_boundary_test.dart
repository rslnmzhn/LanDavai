import 'package:flutter_test/flutter_test.dart';
import 'package:landa/features/history/domain/transfer_history_record.dart';

import 'test_support/test_discovery_controller.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test(
    'DiscoveryController exposes boundary-backed download history without owning a local mirror',
    () async {
      final harness = await TestDiscoveryControllerHarness.create();
      addTearDown(harness.dispose);

      var controllerNotifications = 0;
      void handleControllerChanged() {
        controllerNotifications += 1;
      }

      harness.controller.addListener(handleControllerChanged);
      addTearDown(
        () => harness.controller.removeListener(handleControllerChanged),
      );

      await harness.downloadHistoryBoundary.recordDownload(
        id: 'download-history-1',
        requestId: 'request-1',
        peerName: 'History peer',
        peerIp: '192.168.1.30',
        rootPath: '/tmp/history',
        savedPaths: const <String>['/tmp/history/file.txt'],
        fileCount: 1,
        totalBytes: 25,
        status: TransferHistoryStatus.completed,
        createdAtMs: 100,
      );

      expect(harness.downloadHistoryBoundary.records, hasLength(1));
      expect(harness.controller.downloadHistory, hasLength(1));
      expect(
        harness.controller.downloadHistory.single.id,
        'download-history-1',
      );
      expect(controllerNotifications, greaterThan(0));
    },
  );
}
