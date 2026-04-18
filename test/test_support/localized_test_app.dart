import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:landa/app/localization/app_localization_config.dart';

Widget buildLocalizedTestApp({
  required Widget home,
  ThemeData? theme,
  Locale? locale,
}) {
  return EasyLocalization(
    key: UniqueKey(),
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
          theme: theme,
          locale: context.locale,
          supportedLocales: context.supportedLocales,
          localizationsDelegates: context.localizationDelegates,
          home: home,
        );
      },
    ),
  );
}
