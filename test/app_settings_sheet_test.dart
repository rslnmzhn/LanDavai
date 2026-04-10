import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:landa/features/settings/domain/app_settings.dart';
import 'package:landa/features/settings/presentation/app_settings_sheet.dart';

void main() {
  Future<void> pumpSettings(
    WidgetTester tester, {
    AppSettings settings = AppSettings.defaults,
    List<String> configuredDiscoveryTargets = const <String>[],
    String? Function(String raw)? configuredTargetValidator,
    Future<bool> Function(String raw)? onAddConfiguredDiscoveryTarget,
    Future<void> Function(String value)? onRemoveConfiguredDiscoveryTarget,
    ValueChanged<BackgroundScanIntervalOption>? onBackgroundIntervalChanged,
    ValueChanged<bool>? onDownloadAttemptNotificationsChanged,
    ValueChanged<bool>? onUseStandardAppDownloadFolderChanged,
    ValueChanged<bool>? onMinimizeToTrayChanged,
    ValueChanged<bool>? onLeftHandedModeChanged,
    ValueChanged<String>? onVideoLinkPasswordChanged,
    ValueChanged<int>? onPreviewCacheMaxSizeGbChanged,
    ValueChanged<int>? onPreviewCacheMaxAgeDaysChanged,
    ValueChanged<int>? onClipboardHistoryMaxEntriesChanged,
    ValueChanged<int>? onRecacheParallelWorkersChanged,
  }) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: AppSettingsSheet(
            settings: settings,
            configuredDiscoveryTargets: configuredDiscoveryTargets,
            configuredTargetValidator: configuredTargetValidator ?? (_) => null,
            onAddConfiguredDiscoveryTarget:
                onAddConfiguredDiscoveryTarget ?? (_) async => true,
            onRemoveConfiguredDiscoveryTarget:
                onRemoveConfiguredDiscoveryTarget ?? (_) async {},
            onBackgroundIntervalChanged: onBackgroundIntervalChanged ?? (_) {},
            onDownloadAttemptNotificationsChanged:
                onDownloadAttemptNotificationsChanged ?? (_) {},
            onUseStandardAppDownloadFolderChanged:
                onUseStandardAppDownloadFolderChanged ?? (_) {},
            onMinimizeToTrayChanged: onMinimizeToTrayChanged ?? (_) {},
            onLeftHandedModeChanged: onLeftHandedModeChanged ?? (_) {},
            onVideoLinkPasswordChanged: onVideoLinkPasswordChanged ?? (_) {},
            onPreviewCacheMaxSizeGbChanged:
                onPreviewCacheMaxSizeGbChanged ?? (_) {},
            onPreviewCacheMaxAgeDaysChanged:
                onPreviewCacheMaxAgeDaysChanged ?? (_) {},
            onClipboardHistoryMaxEntriesChanged:
                onClipboardHistoryMaxEntriesChanged ?? (_) {},
            onRecacheParallelWorkersChanged:
                onRecacheParallelWorkersChanged ?? (_) {},
          ),
        ),
      ),
    );
  }

  testWidgets(
    'desktop settings sheet shows download folder switch and calls callback',
    (tester) async {
      bool? changedValue;

      await pumpSettings(
        tester,
        onUseStandardAppDownloadFolderChanged: (value) {
          changedValue = value;
        },
      );
      await tester.tap(find.text('Интерфейс'));
      await tester.pumpAndSettle();

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
      await pumpSettings(tester);
      await tester.tap(find.text('Интерфейс'));
      await tester.pumpAndSettle();

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
        home: Scaffold(
          body: StatefulBuilder(
            builder: (context, setState) {
              return AppSettingsSheet(
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
              );
            },
          ),
        ),
      ),
    );

    await tester.enterText(
      find.widgetWithText(TextField, 'IPv4-адрес устройства'),
      '100.64.0.8',
    );
    final addButton = find.widgetWithText(FilledButton, 'Добавить');
    await tester.ensureVisible(addButton);
    await tester.tap(addButton);
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
    await pumpSettings(
      tester,
      configuredTargetValidator: (_) => 'Введите корректный IPv4-адрес.',
      onAddConfiguredDiscoveryTarget: (_) async => false,
    );

    await tester.enterText(
      find.widgetWithText(TextField, 'IPv4-адрес устройства'),
      'abc',
    );
    final addButton = find.widgetWithText(FilledButton, 'Добавить');
    await tester.ensureVisible(addButton);
    await tester.tap(addButton);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));

    expect(find.text('Введите корректный IPv4-адрес.'), findsOneWidget);
  });

  testWidgets('settings sheet switches tabs by tap and swipe', (tester) async {
    await pumpSettings(tester);

    expect(find.text('Фоновое сканирование сети'), findsOneWidget);
    expect(find.text('Веб-ссылка'), findsNothing);

    await tester.tap(find.text('Доступ'));
    await tester.pumpAndSettle();

    expect(find.text('Веб-ссылка'), findsOneWidget);
    expect(find.text('Фоновое сканирование сети'), findsNothing);

    await tester.fling(find.text('Веб-ссылка'), const Offset(600, 0), 1200);
    await tester.pumpAndSettle();

    expect(find.text('Preview-кэш'), findsOneWidget);
    expect(find.text('Веб-ссылка'), findsNothing);
  });
}
