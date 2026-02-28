import 'package:flutter/material.dart';

import 'app/app.dart';
import 'core/utils/app_notification_service.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await AppNotificationService.instance.initialize();
  runApp(const LandaApp());
}
