import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:landa/core/utils/single_instance_guard.dart';

void main() {
  test('prevents acquiring the same desktop lock twice concurrently', () async {
    final tempDirectory = await Directory.systemTemp.createTemp(
      'landa_single_instance_guard_',
    );
    addTearDown(() async {
      try {
        await tempDirectory.delete(recursive: true);
      } catch (_) {}
    });

    final guard = SingleInstanceGuard(desktopPlatformResolver: () => true);
    final first = await guard.acquire(lockDirectory: tempDirectory);
    addTearDown(first.dispose);

    expect(first.acquired, isTrue);
    expect(first.shouldBlockStartup, isFalse);

    final second = await guard.acquire(lockDirectory: tempDirectory);
    addTearDown(second.dispose);

    expect(second.acquired, isFalse);
    expect(second.shouldBlockStartup, isTrue);
  });

  test(
    'does not block startup when guard is not enforced on android-like path',
    () async {
      final guard = SingleInstanceGuard(desktopPlatformResolver: () => false);

      final handle = await guard.acquire();
      addTearDown(handle.dispose);

      expect(handle.acquired, isFalse);
      expect(handle.shouldBlockStartup, isFalse);
    },
  );
}
