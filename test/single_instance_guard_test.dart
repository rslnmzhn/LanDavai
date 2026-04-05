import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:landa/core/utils/single_instance_guard.dart';

void main() {
  test('prevents acquiring the same desktop lock twice concurrently', () async {
    if (!Platform.isWindows && !Platform.isLinux) {
      return;
    }

    final tempDirectory = await Directory.systemTemp.createTemp(
      'landa_single_instance_guard_',
    );
    addTearDown(() async {
      try {
        await tempDirectory.delete(recursive: true);
      } catch (_) {}
    });

    final guard = const SingleInstanceGuard();
    final first = await guard.acquire(lockDirectory: tempDirectory);
    addTearDown(first.dispose);

    expect(first.acquired, isTrue);

    final second = await guard.acquire(lockDirectory: tempDirectory);
    addTearDown(second.dispose);

    expect(second.acquired, isFalse);
  });
}
