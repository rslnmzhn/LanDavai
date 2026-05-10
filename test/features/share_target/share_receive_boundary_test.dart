import 'package:flutter_test/flutter_test.dart';
import 'package:landa/features/share_target/application/share_receive_boundary.dart';

void main() {
  test('hasPendingShare false on init', () {
    final boundary = ShareReceiveBoundary(
      consumePendingSharedFiles: () async => const <String>[],
    );
    addTearDown(boundary.dispose);

    expect(boundary.hasPendingShare, isFalse);
    expect(boundary.pendingFiles, isEmpty);
  });

  test('hasPendingShare true after inject', () async {
    final boundary = ShareReceiveBoundary(
      consumePendingSharedFiles: () async => const <String>[
        '/cache/shared-a.png',
        '/cache/shared-b.txt',
      ],
    );
    addTearDown(boundary.dispose);

    await boundary.initialize();

    expect(boundary.hasPendingShare, isTrue);
    expect(
      boundary.pendingFiles,
      const <String>['/cache/shared-a.png', '/cache/shared-b.txt'],
    );
  });

  test('clearPendingShare resets state', () async {
    final boundary = ShareReceiveBoundary(
      consumePendingSharedFiles: () async => const <String>['/cache/shared.png'],
    );
    addTearDown(boundary.dispose);
    await boundary.initialize();

    boundary.clearPendingShare();

    expect(boundary.hasPendingShare, isFalse);
    expect(boundary.pendingFiles, isEmpty);
  });
}
