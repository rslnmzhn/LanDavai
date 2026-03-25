import 'package:flutter_test/flutter_test.dart';
import 'package:landa/features/clipboard/domain/clipboard_entry.dart';

import 'test_support/test_discovery_controller.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test(
    'DiscoveryController exposes ClipboardHistoryStore-backed local history without owning a mirror',
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

      await harness.clipboardHistoryStore.appendEntry(
        entry: ClipboardHistoryEntry(
          id: 'clipboard-entry-1',
          type: ClipboardEntryType.text,
          contentHash: 'text:clipboard-entry-1',
          textValue: 'Clipboard entry',
          createdAt: DateTime.fromMillisecondsSinceEpoch(100),
        ),
      );

      expect(harness.clipboardHistoryStore.entries, hasLength(1));
      expect(harness.controller.clipboardHistory, hasLength(1));
      expect(
        harness.controller.clipboardHistory.single.id,
        'clipboard-entry-1',
      );
      expect(controllerNotifications, greaterThan(0));
    },
  );
}
