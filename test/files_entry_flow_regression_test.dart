import 'dart:io';

import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:landa/app/localization/app_localization_config.dart';
import 'package:path/path.dart' as p;

import 'package:landa/features/files/application/file_explorer_contract.dart';
import 'package:landa/features/files/application/files_feature_state_owner.dart';
import 'package:landa/features/files/presentation/file_explorer/local_file_viewer.dart';
import 'package:landa/features/files/presentation/file_explorer_page.dart';

import 'test_support/test_discovery_controller.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late TestDiscoveryControllerHarness harness;

  setUp(() async {
    harness = await TestDiscoveryControllerHarness.create();
    addTearDown(() async {
      await harness.dispose();
    });
  });

  testWidgets('File explorer can launch LocalFileViewerPage', (tester) async {
    _registerWidgetCleanup(tester);
    _registerPhoneViewport(tester);
    final file = File(
      p.join(harness.databaseHarness.rootDirectory.path, 'viewer-sample.txt'),
    );
    await tester.runAsync(() async {
      await file.writeAsString('hello');
    });

    final owner = FilesFeatureStateOwner(
      roots: <FileExplorerRoot>[
        FileExplorerRoot(
          label: 'My files',
          path: 'virtual://viewer',
          virtualFiles: <FileExplorerVirtualFile>[
            FileExplorerVirtualFile(
              path: file.path,
              virtualPath: 'viewer-sample.txt',
              sizeBytes: file.lengthSync(),
              modifiedAt: DateTime(2026, 1, 1),
              changedAt: DateTime(2026, 1, 1),
            ),
          ],
        ),
      ],
    );
    addTearDown(owner.dispose);
    await owner.initialize();

    await tester.pumpWidget(
      buildLocalizedApp(
        home: FileExplorerPage(
          owner: owner,
          previewCacheOwner: harness.previewCacheOwner,
          sharedCacheMaintenanceBoundary:
              harness.sharedCacheMaintenanceBoundary,
        ),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    await tester.pumpAndSettle();
    await _pumpForUi(tester, frames: 20);
    expect(find.text('viewer-sample.txt'), findsOneWidget);
    await tester.tap(find.text('viewer-sample.txt'));
    await _pumpUntilFound(
      tester,
      find.byType(LocalFileViewerPage, skipOffstage: false),
      failureMessage: 'Local file viewer route did not open from file list.',
    );
    await _flushAsync(tester);
    await _closeCurrentRoute(tester, find.byType(LocalFileViewerPage).first);
    await _pumpForUi(tester, frames: 12);
  });
}

Future<void> _pumpForUi(WidgetTester tester, {int frames = 12}) async {
  for (var i = 0; i < frames; i += 1) {
    await tester.pump(const Duration(milliseconds: 50));
  }
}

Future<void> _flushAsync(WidgetTester tester) async {
  await tester.runAsync(() async {
    await Future<void>.delayed(const Duration(milliseconds: 50));
  });
  await _pumpForUi(tester, frames: 4);
}

Future<void> _pumpUntilFound(
  WidgetTester tester,
  Finder finder, {
  String? failureMessage,
  int maxFrames = 120,
}) async {
  for (var i = 0; i < maxFrames; i += 1) {
    await tester.pump(const Duration(milliseconds: 50));
    if (finder.evaluate().isNotEmpty) {
      return;
    }
  }
  throw TestFailure(
    failureMessage ?? 'Expected widget was not found after pumping.',
  );
}

void _registerWidgetCleanup(WidgetTester tester) {
  addTearDown(() async {
    await tester.pumpWidget(const SizedBox.shrink());
    await _pumpForUi(tester);
  });
}

void _registerPhoneViewport(WidgetTester tester) {
  tester.view.physicalSize = const Size(800, 1600);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
}

Future<void> _closeCurrentRoute(WidgetTester tester, Finder anchor) async {
  final context = tester.element(anchor);
  Navigator.of(context).pop();
  await _pumpForUi(tester, frames: 8);
}

Widget buildLocalizedApp({required Widget home, Locale? locale}) {
  return EasyLocalization(
    supportedLocales: AppLocalizationConfig.supportedLocales,
    path: AppLocalizationConfig.assetPath,
    fallbackLocale: AppLocalizationConfig.fallbackLocale,
    startLocale: locale ?? AppLocalizationConfig.startLocale,
    saveLocale: false,
    useOnlyLangCode: true,
    useFallbackTranslations: true,
    child: Builder(
      builder: (context) {
        return MaterialApp(
          locale: context.locale,
          supportedLocales: context.supportedLocales,
          localizationsDelegates: context.localizationDelegates,
          home: home,
        );
      },
    ),
  );
}
