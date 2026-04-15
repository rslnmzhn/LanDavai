import 'package:flutter/material.dart';

class AppLocalizationConfig {
  const AppLocalizationConfig._();

  static const String assetPath = 'assets/translations';
  static const Locale fallbackLocale = Locale('en');
  static const Locale startLocale = Locale('ru');
  static const List<Locale> supportedLocales = <Locale>[
    Locale('en'),
    Locale('ru'),
  ];
}
