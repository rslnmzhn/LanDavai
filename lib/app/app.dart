import 'package:flutter/material.dart';

import '../features/discovery/presentation/discovery_page.dart';
import 'theme/app_theme.dart';

class LandaApp extends StatelessWidget {
  const LandaApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Landa',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.light(),
      home: const DiscoveryPage(),
    );
  }
}

