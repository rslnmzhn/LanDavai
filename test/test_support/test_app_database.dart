import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:landa/core/storage/app_database.dart';

class TestAppDatabaseHarness {
  TestAppDatabaseHarness._({required this.rootDirectory});

  final Directory rootDirectory;
  static const MethodChannel _pathProviderChannel = MethodChannel(
    'plugins.flutter.io/path_provider',
  );

  AppDatabase get database => AppDatabase.instance;

  static Future<TestAppDatabaseHarness> create({
    String prefix = 'landa_test_storage_',
  }) async {
    final binding = TestWidgetsFlutterBinding.ensureInitialized();
    final rootDirectory = await Directory.systemTemp.createTemp(prefix);
    binding.defaultBinaryMessenger.setMockMethodCallHandler(
      _pathProviderChannel,
      (call) async {
        switch (call.method) {
          case 'getApplicationSupportDirectory':
            return rootDirectory.path;
          case 'getTemporaryDirectory':
            return Directory.systemTemp.path;
        }
        return null;
      },
    );
    await AppDatabase.instance.close();
    await AppDatabase.instance.database;
    return TestAppDatabaseHarness._(rootDirectory: rootDirectory);
  }

  Future<void> dispose() async {
    await AppDatabase.instance.close();
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(_pathProviderChannel, null);
    if (await rootDirectory.exists()) {
      await rootDirectory.delete(recursive: true);
    }
  }
}
