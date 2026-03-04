import 'package:flutter/material.dart';
import 'package:media_kit/media_kit.dart';

import 'app/app.dart';
import 'core/utils/app_notification_service.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  MediaKit.ensureInitialized();
  await AppNotificationService.instance.initialize();
  runApp(const LandaApp());
}
