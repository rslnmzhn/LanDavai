import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:landa/features/nearby_transfer/presentation/nearby_transfer_scanner_view.dart';

void main() {
  testWidgets('scanner overlay uses a square frame', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: NearbyTransferScannerView(
            liveScannerSupported: true,
            onPayloadDetected: (_) {},
            previewBuilder: (_) => const ColoredBox(color: Colors.black),
          ),
        ),
      ),
    );
    await tester.pump();

    final frameSize = tester.getSize(
      find.byKey(const Key('nearby-transfer-scanner-frame')),
    );

    expect(frameSize.width, closeTo(frameSize.height, 0.01));
  });

  testWidgets('scanner shows visible feedback on successful detection', (
    tester,
  ) async {
    String? detectedPayload;

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: NearbyTransferScannerView(
            liveScannerSupported: true,
            onPayloadDetected: (payload) {
              detectedPayload = payload;
            },
            previewBuilder: (onDetected) {
              return Center(
                child: FilledButton(
                  key: const Key('nearby-transfer-test-detect-button'),
                  onPressed: () => onDetected('qr-session-payload'),
                  child: const Text('Detect'),
                ),
              );
            },
          ),
        ),
      ),
    );

    expect(
      tester
          .widget<Opacity>(
            find.ancestor(
              of: find.byKey(
                const Key('nearby-transfer-scanner-detection-feedback'),
              ),
              matching: find.byType(Opacity),
            ),
          )
          .opacity,
      0,
    );

    await tester.tap(
      find.byKey(const Key('nearby-transfer-test-detect-button')),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 160));

    expect(detectedPayload, 'qr-session-payload');
    final feedbackOpacity = tester.widget<Opacity>(
      find.ancestor(
        of: find.byKey(const Key('nearby-transfer-scanner-detection-feedback')),
        matching: find.byType(Opacity),
      ),
    );
    expect(feedbackOpacity.opacity, greaterThan(0));
  });
}
