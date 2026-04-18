import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:landa/features/discovery/presentation/discovery_friends_sheet.dart';

import 'test_support/localized_test_app.dart';
import 'test_support/test_discovery_controller.dart';

void main() {
  late TestDiscoveryControllerHarness harness;

  setUp(() async {
    harness = await TestDiscoveryControllerHarness.create();
    addTearDown(() async {
      await harness.dispose();
    });
  });

  testWidgets('Discovery friends sheet resolves migrated strings in English', (
    tester,
  ) async {
    await _pumpFriendsSheet(
      tester,
      harness: harness,
      locale: const Locale('en'),
    );

    expect(find.text('Friends'), findsAtLeastNWidgets(1));
    expect(
      find.text('Friendship requires confirmation from both devices.'),
      findsOneWidget,
    );
    expect(
      find.text(
        'No friends yet.\nOpen a device menu and send a friend request.',
      ),
      findsOneWidget,
    );
  });
}

Future<void> _pumpFriendsSheet(
  WidgetTester tester, {
  required TestDiscoveryControllerHarness harness,
  required Locale locale,
}) async {
  await tester.pumpWidget(const SizedBox.shrink());
  await tester.pump();
  await tester.pumpWidget(
    buildLocalizedTestApp(
      locale: locale,
      home: DefaultTabController(
        length: 2,
        child: Scaffold(
          body: DiscoveryFriendsSheet(
            controller: harness.controller,
            readModel: harness.readModel,
          ),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
  await tester.pump(const Duration(milliseconds: 100));
}
