import 'package:flutter/material.dart';

import '../features/discovery/presentation/discovery_page.dart';
import 'theme/app_theme.dart';

class LanDaApp extends StatelessWidget {
  const LanDaApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'LanDa',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.light(),
      home: const DiscoveryPage(),
    );
  }
}
