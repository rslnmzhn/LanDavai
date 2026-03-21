import 'package:flutter/material.dart';

import 'discovery_page_entry.dart';
import 'theme/app_theme.dart';

class LandaApp extends StatelessWidget {
  const LandaApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Landa',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.light(),
      home: const DiscoveryPageEntry(),
    );
  }
}
