import 'package:flutter/material.dart';
import 'package:media_kit/media_kit.dart';

import 'app/app.dart';
import 'app/duplicate_instance_notice_app.dart';
import 'core/utils/app_notification_service.dart';
import 'core/utils/single_instance_guard.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  MediaKit.ensureInitialized();
  await AppNotificationService.instance.initialize();

  final singleInstanceGuardHandle = await const SingleInstanceGuard().acquire();
  if (singleInstanceGuardHandle.shouldBlockStartup) {
    runApp(const DuplicateInstanceNoticeApp());
    return;
  }
  runApp(
    _StartupGuardApp(
      guardHandle: singleInstanceGuardHandle,
      child: const LandaApp(),
    ),
  );
}

class _StartupGuardApp extends StatefulWidget {
  const _StartupGuardApp({required this.guardHandle, required this.child});

  final SingleInstanceGuardHandle guardHandle;
  final Widget child;

  @override
  State<_StartupGuardApp> createState() => _StartupGuardAppState();
}

class _StartupGuardAppState extends State<_StartupGuardApp> {
  @override
  Widget build(BuildContext context) => widget.child;

  @override
  void dispose() {
    widget.guardHandle.dispose();
    super.dispose();
  }
}
