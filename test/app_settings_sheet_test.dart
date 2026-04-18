import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:landa/app/localization/app_localization_config.dart';
import 'package:landa/features/settings/domain/app_settings.dart';
import 'package:landa/features/settings/presentation/app_settings_tab_sections.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('network tab adds and removes configured discovery targets', (
    tester,
  ) async {
    final controller = TextEditingController();
    final targets = <String>['100.64.0.2'];
    final removed = <String>[];
    var addCalls = 0;

    await tester.pumpWidget(
      buildLocalizedApp(
        home: Scaffold(
          body: StatefulBuilder(
            builder: (context, setState) {
              return AppSettingsNetworkTab(
                settings: AppSettings.defaults,
                configuredDiscoveryTargets: targets,
                configuredTargetController: controller,
                onAddConfiguredTarget: () async {
                  addCalls += 1;
                  setState(() {
                    targets.add(controller.text.trim());
                  });
                },
                onRemoveConfiguredTarget: (value) async {
                  removed.add(value);
                  setState(() {
                    targets.remove(value);
                  });
                },
                onBackgroundIntervalChanged: (_) {},
                onDownloadAttemptNotificationsChanged: (_) {},
              );
            },
          ),
        ),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    await tester.pumpAndSettle();

    await tester.enterText(
      find.widgetWithText(TextField, 'IPv4-адрес устройства'),
      '100.64.0.8',
    );
    await tester.tap(find.widgetWithText(FilledButton, 'Добавить'));
    await tester.pumpAndSettle();

    expect(addCalls, 1);
    expect(find.text('100.64.0.8'), findsWidgets);

    await tester.tap(find.byIcon(Icons.delete_outline_rounded).first);
    await tester.pumpAndSettle();

    expect(removed, <String>['100.64.0.2']);
    expect(find.text('100.64.0.2'), findsNothing);
  });
}

Widget buildLocalizedApp({required Widget home, Locale? locale}) {
  return EasyLocalization(
    supportedLocales: AppLocalizationConfig.supportedLocales,
    path: AppLocalizationConfig.assetPath,
    fallbackLocale: AppLocalizationConfig.fallbackLocale,
    startLocale: locale ?? AppLocalizationConfig.startLocale,
    saveLocale: false,
    useOnlyLangCode: true,
    useFallbackTranslations: true,
    child: Builder(
      builder: (context) {
        return MaterialApp(
          locale: context.locale,
          supportedLocales: context.supportedLocales,
          localizationsDelegates: context.localizationDelegates,
          home: home,
        );
      },
    ),
  );
}
