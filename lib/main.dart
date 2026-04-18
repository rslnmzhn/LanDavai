import 'package:flutter/material.dart';
import 'package:easy_localization/easy_localization.dart';
import 'package:media_kit/media_kit.dart';

import 'app/app.dart';
import 'app/duplicate_instance_notice_app.dart';
import 'app/localization/app_localization_config.dart';
import 'core/utils/app_notification_service.dart';
import 'core/utils/single_instance_guard.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await EasyLocalization.ensureInitialized();
  MediaKit.ensureInitialized();
  await AppNotificationService.instance.initialize();

  final singleInstanceGuardHandle = await const SingleInstanceGuard().acquire();
  if (singleInstanceGuardHandle.shouldBlockStartup) {
    runApp(_buildLocalizedApp(const DuplicateInstanceNoticeApp()));
    return;
  }
  runApp(
    _buildLocalizedApp(
      _StartupGuardApp(
        guardHandle: singleInstanceGuardHandle,
        child: const LandaApp(),
      ),
    ),
  );
}

Widget _buildLocalizedApp(Widget child) {
  return EasyLocalization(
    supportedLocales: AppLocalizationConfig.supportedLocales,
    path: AppLocalizationConfig.assetPath,
    fallbackLocale: AppLocalizationConfig.fallbackLocale,
    startLocale: AppLocalizationConfig.startLocale,
    saveLocale: true,
    useOnlyLangCode: true,
    useFallbackTranslations: true,
    child: child,
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
