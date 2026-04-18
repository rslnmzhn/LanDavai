import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:landa/features/clipboard/application/clipboard_source_scope_store.dart';
import 'package:landa/features/clipboard/presentation/clipboard_source_selector.dart';
import 'package:landa/features/discovery/domain/discovered_device.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets(
    'clipboard selector strings switch locale in place',
    (tester) async {
      final devices = <DiscoveredDevice>[
        DiscoveredDevice(
          ip: '192.168.1.44',
          deviceName: 'Remote A',
          isAppDetected: true,
          lastSeen: DateTime(2026, 4, 18, 12),
        ),
      ];

      await tester.pumpWidget(
        EasyLocalization(
          supportedLocales: const <Locale>[Locale('en'), Locale('ru')],
          path: 'assets/translations',
          fallbackLocale: const Locale('en'),
          startLocale: const Locale('en'),
          saveLocale: false,
          useOnlyLangCode: true,
          useFallbackTranslations: true,
          child: Builder(
            builder: (context) {
              return MaterialApp(
                locale: context.locale,
                supportedLocales: context.supportedLocales,
                localizationsDelegates: context.localizationDelegates,
                home: Scaffold(
                  body: Column(
                    children: [
                      TextButton(
                        onPressed: () => context.setLocale(const Locale('ru')),
                        child: const Text('switch-ru'),
                      ),
                      ClipboardSourceSelector(
                        remoteDevices: devices,
                        selectedSourceId:
                            ClipboardSourceScopeStore.localSourceId,
                        onSelectLocal: () {},
                        onSelectRemote: (_) {},
                      ),
                    ],
                  ),
                ),
              );
            },
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('Clipboard source'), findsOneWidget);
      expect(find.text('Current device'), findsOneWidget);

      await tester.tap(find.text('switch-ru'));
      await tester.pumpAndSettle();

      expect(find.text('Источник буфера обмена'), findsOneWidget);
      expect(find.text('Текущее устройство'), findsOneWidget);
    },
  );
}
