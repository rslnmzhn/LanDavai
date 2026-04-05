import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:landa/features/settings/domain/app_settings.dart';
import 'package:landa/features/settings/presentation/app_settings_sheet.dart';

void main() {
  testWidgets(
    'desktop settings sheet shows download folder switch and calls callback',
    (tester) async {
      bool? changedValue;

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: AppSettingsSheet(
              settings: AppSettings.defaults,
              configuredDiscoveryTargets: const <String>[],
              configuredTargetValidator: (_) => null,
              onAddConfiguredDiscoveryTarget: (_) async => true,
              onRemoveConfiguredDiscoveryTarget: (_) async {},
              onBackgroundIntervalChanged: (_) {},
              onDownloadAttemptNotificationsChanged: (_) {},
              onUseStandardAppDownloadFolderChanged: (value) {
                changedValue = value;
              },
              onMinimizeToTrayChanged: (_) {},
              onLeftHandedModeChanged: (_) {},
              onVideoLinkPasswordChanged: (_) {},
              onPreviewCacheMaxSizeGbChanged: (_) {},
              onPreviewCacheMaxAgeDaysChanged: (_) {},
              onClipboardHistoryMaxEntriesChanged: (_) {},
              onRecacheParallelWorkersChanged: (_) {},
            ),
          ),
        ),
      );

      expect(find.text('Скачивать в стандартную папку Landa'), findsOneWidget);

      await tester.tap(find.text('Скачивать в стандартную папку Landa'));
      await tester.pump();

      expect(changedValue, isFalse);
    },
    variant: const TargetPlatformVariant(<TargetPlatform>{
      TargetPlatform.windows,
    }),
  );

  testWidgets(
    'android settings sheet hides download folder switch',
    (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: AppSettingsSheet(
              settings: AppSettings.defaults,
              configuredDiscoveryTargets: const <String>[],
              configuredTargetValidator: (_) => null,
              onAddConfiguredDiscoveryTarget: (_) async => true,
              onRemoveConfiguredDiscoveryTarget: (_) async {},
              onBackgroundIntervalChanged: (_) {},
              onDownloadAttemptNotificationsChanged: (_) {},
              onUseStandardAppDownloadFolderChanged: (_) {},
              onMinimizeToTrayChanged: (_) {},
              onLeftHandedModeChanged: (_) {},
              onVideoLinkPasswordChanged: (_) {},
              onPreviewCacheMaxSizeGbChanged: (_) {},
              onPreviewCacheMaxAgeDaysChanged: (_) {},
              onClipboardHistoryMaxEntriesChanged: (_) {},
              onRecacheParallelWorkersChanged: (_) {},
            ),
          ),
        ),
      );

      expect(find.text('Скачивать в стандартную папку Landa'), findsNothing);
    },
    variant: const TargetPlatformVariant(<TargetPlatform>{
      TargetPlatform.android,
    }),
  );

  testWidgets('settings sheet adds and removes configured discovery targets', (
    tester,
  ) async {
    final targets = <String>['100.64.0.2'];
    final added = <String>[];
    final removed = <String>[];

    await tester.pumpWidget(
      MaterialApp(
        home: StatefulBuilder(
          builder: (context, setState) {
            return Scaffold(
              body: AppSettingsSheet(
                settings: AppSettings.defaults,
                configuredDiscoveryTargets: targets,
                configuredTargetValidator: (raw) {
                  final value = raw.trim();
                  if (value.isEmpty) {
                    return 'Введите IPv4-адрес.';
                  }
                  if (targets.contains(value)) {
                    return 'Этот адрес уже добавлен.';
                  }
                  return null;
                },
                onAddConfiguredDiscoveryTarget: (value) async {
                  added.add(value.trim());
                  setState(() {
                    targets.add(value.trim());
                  });
                  return true;
                },
                onRemoveConfiguredDiscoveryTarget: (value) async {
                  removed.add(value);
                  setState(() {
                    targets.remove(value);
                  });
                },
                onBackgroundIntervalChanged: (_) {},
                onDownloadAttemptNotificationsChanged: (_) {},
                onUseStandardAppDownloadFolderChanged: (_) {},
                onMinimizeToTrayChanged: (_) {},
                onLeftHandedModeChanged: (_) {},
                onVideoLinkPasswordChanged: (_) {},
                onPreviewCacheMaxSizeGbChanged: (_) {},
                onPreviewCacheMaxAgeDaysChanged: (_) {},
                onClipboardHistoryMaxEntriesChanged: (_) {},
                onRecacheParallelWorkersChanged: (_) {},
              ),
            );
          },
        ),
      ),
    );

    await tester.enterText(
      find.widgetWithText(TextField, 'IPv4-адрес устройства'),
      '100.64.0.8',
    );
    await tester.tap(find.text('Добавить'));
    await tester.pump();

    expect(added, <String>['100.64.0.8']);
    expect(find.text('100.64.0.8'), findsOneWidget);

    await tester.tap(find.byIcon(Icons.delete_outline_rounded).first);
    await tester.pump();

    expect(removed, <String>['100.64.0.2']);
    expect(find.text('100.64.0.2'), findsNothing);
  });

  testWidgets('settings sheet shows validation for invalid configured target', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: AppSettingsSheet(
            settings: AppSettings.defaults,
            configuredDiscoveryTargets: const <String>[],
            configuredTargetValidator: (_) => 'Введите корректный IPv4-адрес.',
            onAddConfiguredDiscoveryTarget: (_) async => false,
            onRemoveConfiguredDiscoveryTarget: (_) async {},
            onBackgroundIntervalChanged: (_) {},
            onDownloadAttemptNotificationsChanged: (_) {},
            onUseStandardAppDownloadFolderChanged: (_) {},
            onMinimizeToTrayChanged: (_) {},
            onLeftHandedModeChanged: (_) {},
            onVideoLinkPasswordChanged: (_) {},
            onPreviewCacheMaxSizeGbChanged: (_) {},
            onPreviewCacheMaxAgeDaysChanged: (_) {},
            onClipboardHistoryMaxEntriesChanged: (_) {},
            onRecacheParallelWorkersChanged: (_) {},
          ),
        ),
      ),
    );

    await tester.enterText(
      find.widgetWithText(TextField, 'IPv4-адрес устройства'),
      'abc',
    );
    await tester.tap(find.text('Добавить'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));

    expect(find.text('Введите корректный IPv4-адрес.'), findsOneWidget);
  });
}
