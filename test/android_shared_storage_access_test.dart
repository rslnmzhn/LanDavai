import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:landa/features/discovery/application/android_shared_storage_access.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const channelName = 'landa/test_shared_storage_access';
  const channel = MethodChannel(channelName);

  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, null);
  });

  test(
    'non-Android access is always available without channel calls',
    () async {
      var channelCalls = 0;
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, (call) async {
            channelCalls += 1;
            return false;
          });
      final access = AndroidSharedStorageAccess(
        channel: channel,
        isAndroidProvider: () => false,
      );

      expect(await access.hasAccess(), isTrue);
      expect(await access.requestAccess(), isTrue);
      expect(channelCalls, 0);
    },
  );

  test('hasAccess reads Android shared storage permission channel', () async {
    final calls = <String>[];
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
          calls.add(call.method);
          return true;
        });
    final access = AndroidSharedStorageAccess(
      channel: channel,
      isAndroidProvider: () => true,
    );

    expect(await access.hasAccess(), isTrue);
    expect(calls, <String>['canAccessSharedStorage']);
  });

  test('requestAccess opens settings and rechecks permission', () async {
    final calls = <String>[];
    var granted = false;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
          calls.add(call.method);
          if (call.method == 'requestSharedStorageAccess') {
            granted = true;
            return null;
          }
          return granted;
        });
    final access = AndroidSharedStorageAccess(
      channel: channel,
      isAndroidProvider: () => true,
    );

    expect(await access.requestAccess(), isTrue);
    expect(calls, <String>[
      'canAccessSharedStorage',
      'requestSharedStorageAccess',
      'canAccessSharedStorage',
    ]);
  });

  test('logs and denies permission channel failures', () async {
    final logs = <String>[];
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
          throw PlatformException(code: 'boom');
        });
    final access = AndroidSharedStorageAccess(
      channel: channel,
      isAndroidProvider: () => true,
      log: logs.add,
    );

    expect(await access.hasAccess(), isFalse);
    expect(logs.single, contains('Failed to check shared storage permission'));
  });
}
