import 'package:flutter/material.dart';

import '../features/discovery/presentation/discovery_page.dart';
import 'theme/app_theme.dart';

class IpTransfererApp extends StatelessWidget {
  const IpTransfererApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'IP Transferer',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.light(),
      home: const DiscoveryPage(),
    );
  }
}
