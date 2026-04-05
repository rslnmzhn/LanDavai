import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:landa/features/nearby_transfer/presentation/nearby_transfer_qr_view.dart';

void main() {
  testWidgets(
    'qr view keeps the qr shell centered while pulse animation stays decorative',
    (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: Center(child: NearbyTransferQrView(payload: 'test-payload')),
          ),
        ),
      );
      await tester.pump(const Duration(milliseconds: 120));

      final stageCenter = tester.getCenter(
        find.byKey(const Key('nearby-transfer-qr-stage')),
      );
      final shellCenter = tester.getCenter(
        find.byKey(const Key('nearby-transfer-qr-shell')),
      );
      final qrCenter = tester.getCenter(
        find.byKey(const Key('nearby-transfer-qr-image')),
      );

      expect(shellCenter.dx, closeTo(stageCenter.dx, 0.01));
      expect(shellCenter.dy, closeTo(stageCenter.dy, 0.01));
      expect(qrCenter.dx, closeTo(stageCenter.dx, 0.01));
      expect(qrCenter.dy, closeTo(stageCenter.dy, 0.01));

      expect(
        find.byKey(const Key('nearby-transfer-qr-pulse-0')),
        findsOneWidget,
      );
      expect(
        find.byKey(const Key('nearby-transfer-qr-pulse-1')),
        findsOneWidget,
      );
      expect(
        find.byKey(const Key('nearby-transfer-qr-pulse-2')),
        findsOneWidget,
      );
    },
  );
}
