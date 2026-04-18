import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:landa/features/nearby_transfer/presentation/nearby_transfer_entry_sheet.dart';

import 'test_support/fake_nearby_transfer.dart';
import 'test_support/localized_test_app.dart';
import 'test_support/test_discovery_controller.dart';

void main() {
  late TestDiscoveryControllerHarness harness;

  setUp(() async {
    harness = await TestDiscoveryControllerHarness.create();
  });

  tearDown(() async {
    await harness.dispose();
  });

  testWidgets('entry sheet closes immediately when disconnected', (
    tester,
  ) async {
    final store = buildTestNearbyTransferStore(readModel: harness.readModel);
    addTearDown(store.dispose);
    addTearDown(() async {
      await tester.pumpWidget(const SizedBox.shrink());
      await _pumpForUi(tester, frames: 4);
    });
    const launchAnchorKey = Key('nearby-sheet-launch-anchor');

    await tester.pumpWidget(
      buildLocalizedTestApp(
        home: Scaffold(
          body: Builder(
            builder: (context) {
              return const SizedBox(key: launchAnchorKey);
            },
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    final launchContext = tester.element(find.byKey(launchAnchorKey));
    unawaited(
      showNearbyTransferEntrySheet(context: launchContext, sessionStore: store),
    );
    await _pumpForUi(tester);
    await tester.tap(find.byTooltip('Закрыть'));
    await _pumpForUi(tester);

    expect(find.text('Разорвать соединение?'), findsNothing);
    expect(find.text('Nearby transfer'), findsNothing);

    await store.resetForEntrySelection();
  });
}

Future<void> _pumpForUi(WidgetTester tester, {int frames = 8}) async {
  for (var i = 0; i < frames; i += 1) {
    await tester.pump(const Duration(milliseconds: 50));
  }
}
