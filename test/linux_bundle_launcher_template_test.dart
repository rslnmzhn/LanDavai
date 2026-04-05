import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test(
    'linux raw bundle launcher includes guided recovery for libmpv.so.1',
    () async {
      final template = await File(
        'linux/runner/landa_launcher.sh.in',
      ).readAsString();

      expect(
        template,
        contains(r'REAL_BINARY="${BUNDLE_DIR}/@BINARY_NAME@-bin"'),
      );
      expect(template, contains('libmpv.so.1'));
      expect(
        template,
        contains('sudo apt-get update && sudo apt-get install -y libmpv1'),
      );
      expect(
        template,
        contains('Automatic installation is not started silently.'),
      );
      expect(template, contains(r'exec "${REAL_BINARY}" "$@"'));
    },
  );
}
