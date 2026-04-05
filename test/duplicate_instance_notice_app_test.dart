import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:landa/app/duplicate_instance_notice_app.dart';

void main() {
  testWidgets('renders duplicate-instance notice and closes on action', (
    tester,
  ) async {
    var closeCalls = 0;

    await tester.pumpWidget(
      DuplicateInstanceNoticeApp(
        onClose: () {
          closeCalls += 1;
        },
      ),
    );

    expect(find.text('Landa уже запущена'), findsOneWidget);
    expect(
      find.textContaining('На этом устройстве уже работает другой экземпляр'),
      findsOneWidget,
    );

    await tester.tap(find.widgetWithText(FilledButton, 'Закрыть'));
    await tester.pump();

    expect(closeCalls, 1);
  });
}
