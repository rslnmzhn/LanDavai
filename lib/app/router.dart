import 'package:flutter/material.dart';

import 'discovery_page_entry.dart';

Route<dynamic> onGenerateRoute(RouteSettings settings) {
  return MaterialPageRoute<void>(
    builder: (_) => const DiscoveryPageEntry(),
    settings: settings,
  );
}
