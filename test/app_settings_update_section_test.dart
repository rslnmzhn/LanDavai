import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:landa/app/update/application/app_update_boundary.dart';
import 'package:landa/app/update/domain/app_update_models.dart';
import 'package:landa/features/settings/domain/app_settings.dart';
import 'package:landa/features/settings/presentation/app_settings_tab_sections.dart';

import 'test_support/localized_test_app.dart';

void main() {
  testWidgets('settings network tab shows the update-available surface', (
    tester,
  ) async {
    final appUpdateBoundary = AppUpdateBoundary(
      currentVersionLoader: () async => '1.0.0',
      latestReleaseLoader: () async => const AppUpdateRelease(
        version: '1.1.0',
        tag: 'v1.1.0',
        releasePageUrl:
            'https://github.com/rslnmzhn/LanDavai/releases/tag/v1.1.0',
      ),
    );
    await appUpdateBoundary.initialize();
    await appUpdateBoundary.checkForUpdates();

    await tester.pumpWidget(
      buildLocalizedTestApp(
        locale: const Locale('en'),
        home: Scaffold(
          body: AppSettingsNetworkTab(
            settings: AppSettings.defaults,
            appUpdateBoundary: appUpdateBoundary,
            configuredDiscoveryTargets: const <String>[],
            configuredTargetController: TextEditingController(),
            onAddConfiguredTarget: () async {},
            onRemoveConfiguredTarget: (_) async {},
            onBackgroundIntervalChanged: (_) {},
            onDownloadAttemptNotificationsChanged: (_) {},
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.scrollUntilVisible(
      find.text('Updates'),
      300,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.pumpAndSettle();

    expect(find.text('Updates'), findsOneWidget);
    expect(find.text('Current version: 1.0.0'), findsOneWidget);
    expect(find.text('Latest release: 1.1.0'), findsOneWidget);
    expect(find.text('Update available: 1.1.0'), findsOneWidget);
    expect(
      find.widgetWithText(FilledButton, 'Check for updates'),
      findsOneWidget,
    );
  });
}
