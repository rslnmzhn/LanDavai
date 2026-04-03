import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:landa/features/clipboard/application/clipboard_source_scope_store.dart';
import 'package:landa/features/clipboard/presentation/clipboard_source_selector.dart';
import 'package:landa/features/discovery/domain/discovered_device.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets(
    'clipboard source selector shows current device and one chip per LAN device in a horizontal row',
    (tester) async {
      final devices = List<DiscoveredDevice>.generate(6, (index) {
        return DiscoveredDevice(
          ip: '192.168.1.${40 + index}',
          deviceName: 'Peer device $index',
          isAppDetected: true,
          lastSeen: DateTime(2026, 4, 1, 10, index),
        );
      });
      var selectedSourceId = ClipboardSourceScopeStore.localSourceId;

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SizedBox(
              width: 280,
              child: StatefulBuilder(
                builder: (context, setState) {
                  return ClipboardSourceSelector(
                    remoteDevices: devices,
                    selectedSourceId: selectedSourceId,
                    onSelectLocal: () {
                      setState(() {
                        selectedSourceId =
                            ClipboardSourceScopeStore.localSourceId;
                      });
                    },
                    onSelectRemote: (device) {
                      setState(() {
                        selectedSourceId =
                            ClipboardSourceScopeStore.remoteSourceId(device.ip);
                      });
                    },
                  );
                },
              ),
            ),
          ),
        ),
      );
      await tester.pump();

      expect(find.text('Current device'), findsOneWidget);
      expect(find.widgetWithText(ChoiceChip, 'Peer device 0'), findsOneWidget);
      expect(find.widgetWithText(ChoiceChip, 'Peer device 5'), findsOneWidget);
      expect(find.byType(ChoiceChip), findsNWidgets(devices.length + 1));
      expect(
        find.descendant(
          of: find.byType(ClipboardSourceSelector),
          matching: find.byType(SingleChildScrollView),
        ),
        findsOneWidget,
      );
      expect(
        find.descendant(
          of: find.byType(ClipboardSourceSelector),
          matching: find.byType(Wrap),
        ),
        findsNothing,
      );
      expect(
        find.descendant(
          of: find.byType(ClipboardSourceSelector),
          matching: find.byType(Scrollbar),
        ),
        findsNothing,
      );

      final before = tester.getRect(
        find.widgetWithText(ChoiceChip, 'Peer device 5'),
      );
      expect(before.left, greaterThan(280));

      await tester.drag(
        find.byKey(const Key('clipboard-source-chip-row')),
        const Offset(-260, 0),
      );
      await tester.pump();

      final after = tester.getRect(
        find.widgetWithText(ChoiceChip, 'Peer device 5'),
      );
      expect(after.left, lessThan(before.left));
    },
  );
}
