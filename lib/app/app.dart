import 'package:flutter/material.dart';
import 'package:easy_localization/easy_localization.dart';

import 'discovery_page_entry.dart';
import 'theme/app_theme.dart';

class LandaApp extends StatelessWidget {
  const LandaApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      locale: context.locale,
      supportedLocales: context.supportedLocales,
      localizationsDelegates: context.localizationDelegates,
      onGenerateTitle: (BuildContext context) => 'app.title'.tr(),
      debugShowCheckedModeBanner: false,
      theme: AppTheme.light(),
      home: const DiscoveryPageEntry(),
    );
  }
}
