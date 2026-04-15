import 'dart:convert';
import 'dart:io';

import 'package:easy_localization/easy_localization.dart';
import 'package:easy_localization/src/localization.dart';
import 'package:easy_localization/src/translations.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:landa/app/duplicate_instance_notice_app.dart';
import 'package:landa/app/localization/app_localization_config.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets(
    'renders duplicate-instance notice from JSON assets and closes on action',
    (tester) async {
      var closeCalls = 0;

      await tester.pumpWidget(
        EasyLocalization(
          supportedLocales: AppLocalizationConfig.supportedLocales,
          path: AppLocalizationConfig.assetPath,
          fallbackLocale: AppLocalizationConfig.fallbackLocale,
          startLocale: AppLocalizationConfig.startLocale,
          saveLocale: false,
          useOnlyLangCode: true,
          useFallbackTranslations: true,
          child: DuplicateInstanceNoticeApp(
            onClose: () {
              closeCalls += 1;
            },
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('Landa уже запущена'), findsOneWidget);
      expect(
        find.textContaining('На этом устройстве уже работает другой экземпляр'),
        findsOneWidget,
      );

      await tester.tap(find.widgetWithText(FilledButton, 'Закрыть'));
      await tester.pump();

      expect(closeCalls, 1);
    },
  );

  test('loads fallback translations from the JSON asset set', () {
    final ruJson = File(
      '${AppLocalizationConfig.assetPath}/ru.json',
    ).readAsStringSync();
    final enJson = File(
      '${AppLocalizationConfig.assetPath}/en.json',
    ).readAsStringSync();

    expect(
      Localization.load(
        AppLocalizationConfig.startLocale,
        translations: Translations(
          Map<String, dynamic>.from(jsonDecode(ruJson) as Map<String, dynamic>),
        ),
        fallbackTranslations: Translations(
          Map<String, dynamic>.from(jsonDecode(enJson) as Map<String, dynamic>),
        ),
      ),
      isTrue,
    );
    expect(
      Localization.instance.tr('localization.fallback_probe'),
      'Fallback text',
    );
  });
}
