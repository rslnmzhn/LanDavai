import 'package:flutter/material.dart';

import '../features/discovery/presentation/discovery_page.dart';

Route<dynamic> onGenerateRoute(RouteSettings settings) {
  return MaterialPageRoute<void>(
    builder: (_) => const DiscoveryPage(),
    settings: settings,
  );
}
