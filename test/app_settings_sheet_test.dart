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
}
