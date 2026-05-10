import 'package:flutter/material.dart';

import '../features/discovery/application/discovery_read_model.dart';
import '../features/share_target/application/share_receive_boundary.dart';
import '../features/share_target/presentation/share_target_page.dart';
import '../features/transfer/application/transfer_session_coordinator.dart';
import 'discovery_page_entry.dart';

class AppRoutes {
  static const String shareTarget = '/share-target';

  const AppRoutes._();
}

class ShareTargetRouteArguments {
  const ShareTargetRouteArguments({
    required this.shareReceiveBoundary,
    required this.readModel,
    required this.transferSessionCoordinator,
  });

  final ShareReceiveBoundary shareReceiveBoundary;
  final DiscoveryReadModel readModel;
  final TransferSessionCoordinator transferSessionCoordinator;
}

Route<dynamic> onGenerateRoute(RouteSettings settings) {
  if (settings.name == AppRoutes.shareTarget) {
    final arguments = settings.arguments;
    if (arguments is ShareTargetRouteArguments) {
      return MaterialPageRoute<void>(
        builder: (_) => ShareTargetPage(
          shareReceiveBoundary: arguments.shareReceiveBoundary,
          readModel: arguments.readModel,
          transferSessionCoordinator: arguments.transferSessionCoordinator,
        ),
        settings: settings,
      );
    }
  }

  return MaterialPageRoute<void>(
    builder: (_) => const DiscoveryPageEntry(),
    settings: settings,
  );
}
