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
    expect(boundary.pendingFiles, const <String>[
      '/cache/shared-a.png',
      '/cache/shared-b.txt',
    ]);
  });

  test('clearPendingShare resets state', () async {
    final boundary = ShareReceiveBoundary(
      consumePendingSharedFiles: () async => const <String>[
        '/cache/shared.png',
      ],
    );
    addTearDown(boundary.dispose);
    await boundary.initialize();

    boundary.clearPendingShare();

    expect(boundary.hasPendingShare, isFalse);
    expect(boundary.pendingFiles, isEmpty);
  });

  test('clearPendingShare discards consumed staging copies', () async {
    final discarded = <List<String>>[];
    final boundary = ShareReceiveBoundary(
      consumePendingSharedFiles: () async => const <String>[
        '/cache/share_intent/a.png',
        '/cache/share_intent/b.txt',
      ],
      discardConsumedFiles: (paths) async {
        discarded.add(List<String>.of(paths));
        return paths.length;
      },
    );
    addTearDown(boundary.dispose);

    await boundary.initialize();
    expect(boundary.hasPendingShare, isTrue);

    boundary.clearPendingShare();

    await pumpEventQueue();
    expect(boundary.hasPendingShare, isFalse);
    expect(discarded, hasLength(1));
    expect(discarded.single, <String>[
      '/cache/share_intent/a.png',
      '/cache/share_intent/b.txt',
    ]);
  });

  test('clearPendingShare clears state even when discarding fails', () async {
    final boundary = ShareReceiveBoundary(
      consumePendingSharedFiles: () async => const <String>[
        '/cache/share_intent/a.png',
      ],
      discardConsumedFiles: (paths) async {
        throw StateError('channel unavailable');
      },
    );
    addTearDown(boundary.dispose);

    await boundary.initialize();
    expect(boundary.hasPendingShare, isTrue);

    boundary.clearPendingShare();

    await pumpEventQueue();
    expect(boundary.hasPendingShare, isFalse);
  });

  test('failed send keeps staging copies available for retry', () async {
    final discarded = <List<String>>[];
    final boundary = ShareReceiveBoundary(
      consumePendingSharedFiles: () async => const <String>[
        '/cache/share_intent/a.png',
      ],
      discardConsumedFiles: (paths) async {
        discarded.add(paths);
        return paths.length;
      },
    );
    addTearDown(boundary.dispose);

    await boundary.initialize();
    expect(boundary.hasPendingShare, isTrue);

    // No clearPendingShare call: a failed send must keep the files.
    await pumpEventQueue();
    expect(boundary.hasPendingShare, isTrue);
    expect(discarded, isEmpty);
  });
}
