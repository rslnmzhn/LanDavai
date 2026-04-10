import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

import 'package:landa/app/discovery_page_entry.dart';
import 'package:landa/app/theme/app_spacing.dart';
import 'package:landa/features/discovery/data/discovery_network_interface_catalog.dart';
import 'package:landa/features/discovery/data/lan_packet_codec.dart';
import 'package:landa/features/discovery/data/lan_protocol_events.dart';
import 'package:landa/features/discovery/domain/discovered_device.dart';
import 'package:landa/features/discovery/presentation/discovery_page.dart';
import 'package:landa/features/transfer/data/transfer_storage_service.dart';

import 'test_support/test_discovery_controller.dart';

void main() {
  late TestDiscoveryControllerHarness harness;

  setUp(() async {
    harness = await TestDiscoveryControllerHarness.create();
    addTearDown(() async {
      await harness.dispose();
    });
  });

  testWidgets(
    'DiscoveryPage renders with injected dependencies and does not own controller disposal',
    (tester) async {
      _registerWidgetCleanup(tester);
      await _pumpDiscoveryPage(tester, harness: harness);

      expect(find.text('Landa devices'), findsOneWidget);
      expect(harness.controller.startCalls, 0);

      await tester.pumpWidget(const SizedBox.shrink());
      await _pumpForUi(tester);

      expect(harness.controller.disposeCalls, 0);
    },
  );

  testWidgets(
    'DiscoveryPageEntry starts injected controller above the screen lifecycle',
    (tester) async {
      _registerWidgetCleanup(tester);
      final desktopWindowService = TrackingDesktopWindowService();
      final transferStorageService = StubTransferStorageService(
        rootDirectory: harness.databaseHarness.rootDirectory,
      );
      final composition = harness.createEntryComposition(
        desktopWindowService: desktopWindowService,
        transferStorageService: transferStorageService,
      );

      await tester.pumpWidget(
        MaterialApp(home: DiscoveryPageEntry(composition: composition)),
      );
      await tester.pumpAndSettle();

      expect(find.text('Landa devices'), findsOneWidget);
      expect(harness.controller.startCalls, 1);
      expect(desktopWindowService.setMinimizeCalls, 1);

      await tester.pumpWidget(const SizedBox.shrink());
      await _pumpForUi(tester);

      expect(harness.controller.disposeCalls, 0);
    },
  );

  testWidgets(
    'DiscoveryPage shows a unified device list without subnet tabs on the main surface',
    (tester) async {
      _registerWidgetCleanup(tester);
      await tester.binding.setSurfaceSize(const Size(320, 900));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      harness.discoveryNetworkInterfaceCatalog.replaceInterfaces(
        const <DiscoveryRawNetworkInterface>[
          DiscoveryRawNetworkInterface(
            name: 'Office LAN',
            index: 1,
            ipv4Addresses: <String>['192.168.1.10', '192.168.1.11'],
          ),
          DiscoveryRawNetworkInterface(
            name: 'Tailscale',
            index: 2,
            ipv4Addresses: <String>['100.90.1.10'],
          ),
          DiscoveryRawNetworkInterface(
            name: 'ZeroTier',
            index: 3,
            ipv4Addresses: <String>['172.30.1.10'],
          ),
          DiscoveryRawNetworkInterface(
            name: 'Hamachi',
            index: 4,
            ipv4Addresses: <String>['25.10.10.5'],
          ),
          DiscoveryRawNetworkInterface(
            name: 'Warehouse VLAN',
            index: 5,
            ipv4Addresses: <String>['10.55.0.10'],
          ),
        ],
      );
      await harness.discoveryNetworkScopeStore.refresh();
      harness.controller.setTestDevices(<DiscoveredDevice>[
        DiscoveredDevice(
          ip: '192.168.1.77',
          deviceName: 'Office laptop',
          isAppDetected: true,
          isReachable: true,
          lastSeen: DateTime(2026, 1, 1, 10),
        ),
        DiscoveredDevice(
          ip: '100.90.1.77',
          deviceName: 'Tailscale peer',
          isAppDetected: true,
          isReachable: true,
          lastSeen: DateTime(2026, 1, 1, 10),
        ),
        DiscoveredDevice(
          ip: '172.30.1.77',
          deviceName: 'ZeroTier peer',
          isAppDetected: true,
          isReachable: true,
          lastSeen: DateTime(2026, 1, 1, 10),
        ),
      ]);

      await _pumpDiscoveryPage(tester, harness: harness);

      expect(find.text('Office laptop'), findsOneWidget);
      expect(find.text('Tailscale peer'), findsOneWidget);
      expect(find.text('ZeroTier peer'), findsNothing);
      expect(
        find.byKey(const Key('discovery-network-scope-chip-row')),
        findsNothing,
      );
      expect(find.text('Network scope'), findsNothing);
      expect(find.text('Все'), findsNothing);
      expect(find.text('Office LAN'), findsNothing);
      expect(find.text('Tailscale'), findsNothing);
      expect(find.text('ZeroTier'), findsNothing);
      expect(find.widgetWithText(ChoiceChip, 'Warehouse VLAN'), findsNothing);

      await tester.dragUntilVisible(
        find.text('ZeroTier peer'),
        find.byType(ListView),
        const Offset(0, -240),
      );
      await _pumpForUi(tester, frames: 4);

      expect(find.text('ZeroTier peer'), findsOneWidget);
    },
  );

  testWidgets(
    'DiscoveryPage empty state no longer references subnet scope switching',
    (tester) async {
      _registerWidgetCleanup(tester);
      await _pumpDiscoveryPage(tester, harness: harness);

      expect(find.text('No devices found yet'), findsOneWidget);
      expect(
        find.text('Make sure you are on the same Wi-Fi / LAN and refresh.'),
        findsOneWidget,
      );
      expect(find.textContaining('switch back to'), findsNothing);
      expect(find.text('No devices found in this network'), findsNothing);
    },
  );

  testWidgets(
    'DiscoveryPage wide layout keeps sidebar flush right and action bar inside content pane',
    (tester) async {
      _registerWidgetCleanup(tester);
      await tester.binding.setSurfaceSize(const Size(3200, 1800));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetDevicePixelRatio);

      await _pumpDiscoveryPage(
        tester,
        harness: harness,
        platform: TargetPlatform.windows,
      );

      expect(
        find.byKey(const Key('discovery-wide-layout-header')),
        findsOneWidget,
      );

      final scaffoldRect = tester.getRect(find.byType(Scaffold));
      final headerRect = tester.getRect(
        find.byKey(const Key('discovery-wide-layout-header')),
      );
      final sidePanelRect = tester.getRect(
        find.byKey(const Key('discovery-wide-layout-side-panel')),
      );
      final actionBarRect = tester.getRect(
        find.byKey(const Key('discovery-wide-layout-action-bar')),
      );
      final sendButtonRect = tester.getRect(
        find.widgetWithText(FilledButton, 'Подключиться'),
      );

      expect(headerRect.top, lessThan(AppSpacing.xl));
      expect(sidePanelRect.top, closeTo(scaffoldRect.top, 0.01));
      expect(sidePanelRect.right, closeTo(scaffoldRect.right, 0.01));
      expect(actionBarRect.right, lessThanOrEqualTo(sidePanelRect.left));
      expect(sendButtonRect.right, lessThanOrEqualTo(sidePanelRect.left));
    },
  );

  testWidgets(
    'DiscoveryPage receive flow starts remote browse through RemoteShareBrowser',
    (tester) async {
      _registerWidgetCleanup(tester);
      await _pumpDiscoveryPage(tester, harness: harness);

      await tester.tap(find.widgetWithText(FilledButton, 'Принять'));
      await tester.pump();
      await _pumpForUi(tester);

      expect(harness.remoteShareBrowser.startBrowseCalls, 1);
      expect(find.text('Выбор файлов из LAN'), findsOneWidget);

      await _closeCurrentRoute(tester, find.text('Выбор файлов из LAN'));
      await (harness.controller.lastLoadRemoteShareOptionsFuture ??
          Future<void>.value());
      await tester.pump();
    },
  );

  testWidgets('DiscoveryPage send action opens nearby transfer entry sheet', (
    tester,
  ) async {
    _registerWidgetCleanup(tester);
    await _pumpDiscoveryPage(tester, harness: harness);

    await tester.tap(find.widgetWithText(FilledButton, 'Подключиться'));
    await tester.pumpAndSettle();

    expect(find.text('Nearby transfer'), findsOneWidget);
    expect(find.text('Принять файлы'), findsOneWidget);
    expect(find.text('Отдать файлы'), findsOneWidget);
  });

  testWidgets('DiscoveryPage menu opens a dedicated friends screen', (
    tester,
  ) async {
    _registerWidgetCleanup(tester);
    await _pumpDiscoveryPage(tester, harness: harness);

    await _openMenu(tester);
    expect(find.byType(Drawer), findsNothing);
    expect(
      find.byKey(const Key('discovery-menu-action-friends')),
      findsOneWidget,
    );

    await tester.tap(find.byKey(const Key('discovery-menu-action-friends')));
    await _pumpForUi(tester);

    expect(find.text('Menu'), findsNothing);
    expect(
      find.text('Friendship requires confirmation from both devices.'),
      findsOneWidget,
    );
  });

  testWidgets('DiscoveryPage menu opens settings on a dedicated screen', (
    tester,
  ) async {
    _registerWidgetCleanup(tester);
    await _pumpDiscoveryPage(tester, harness: harness);

    await _openMenu(tester);
    expect(
      find.byKey(const Key('discovery-menu-action-settings')),
      findsOneWidget,
    );
    await tester.tap(find.byKey(const Key('discovery-menu-action-settings')));
    await _pumpForUi(tester);

    expect(find.text('Настройки'), findsOneWidget);
    expect(find.text('Пароль веб-ссылки'), findsOneWidget);
  });

  testWidgets(
    'DiscoveryPage menu opens clipboard on a dedicated screen with remote projection still visible',
    (tester) async {
      _registerWidgetCleanup(tester);
      harness.controller.setTestDevices(<DiscoveredDevice>[
        DiscoveredDevice(
          ip: '192.168.1.44',
          deviceName: 'Remote clipboard',
          isTrusted: true,
          isAppDetected: true,
          isReachable: true,
          lastSeen: DateTime(2026, 1, 1, 10),
        ),
      ]);

      final requestId = harness.remoteClipboardProjectionStore.beginRequest(
        ownerIp: '192.168.1.44',
        localDeviceMac: harness.controller.localDeviceMac,
      );
      harness.remoteClipboardProjectionStore.applyCatalog(
        ClipboardCatalogEvent(
          requestId: requestId,
          ownerIp: '192.168.1.44',
          ownerName: 'Remote clipboard',
          ownerMacAddress: '',
          observedAt: DateTime(2026, 1, 1, 10),
          entries: const <ClipboardCatalogItem>[
            ClipboardCatalogItem(
              id: 'remote-text-1',
              entryType: 'text',
              createdAtMs: 1704100000000,
              textValue: 'Remote hello',
            ),
          ],
        ),
      );
      harness.remoteClipboardProjectionStore.finishRequest(
        requestId: requestId,
      );

      await _pumpDiscoveryPage(tester, harness: harness);

      await _openMenu(tester);
      await tester.tap(
        find.byKey(const Key('discovery-menu-action-clipboard')),
      );
      await _pumpForUi(tester);

      expect(find.text('Clipboard'), findsOneWidget);
      expect(find.widgetWithText(ChoiceChip, 'Current device'), findsOneWidget);
      expect(
        find.widgetWithText(ChoiceChip, 'Remote clipboard'),
        findsOneWidget,
      );
      expect(
        find.text('History is empty. Copy text or image to start.'),
        findsOneWidget,
      );
      expect(find.text('Remote hello'), findsNothing);

      await tester.tap(find.widgetWithText(ChoiceChip, 'Remote clipboard'));
      await _pumpForUi(tester);

      expect(
        find.text('History is empty. Copy text or image to start.'),
        findsNothing,
      );
      expect(find.text('Remote hello'), findsOneWidget);
    },
  );

  testWidgets('DiscoveryPage menu opens history on a dedicated screen', (
    tester,
  ) async {
    _registerWidgetCleanup(tester);
    await _pumpDiscoveryPage(tester, harness: harness);

    await _openMenu(tester);
    await tester.tap(
      find.byKey(const Key('discovery-menu-action-download-history')),
    );
    await _pumpForUi(tester);

    expect(find.text('История загрузок'), findsOneWidget);
    expect(find.text('История загрузок пока пустая'), findsOneWidget);
  });

  testWidgets(
    'DiscoveryPage device actions menu still opens rename and friend actions for visible devices',
    (tester) async {
      _registerWidgetCleanup(tester);
      harness.controller.setTestDevices(<DiscoveredDevice>[
        DiscoveredDevice(
          ip: '192.168.1.77',
          deviceName: 'Office laptop',
          isAppDetected: true,
          isReachable: true,
          lastSeen: DateTime(2026, 1, 1, 11),
        ),
      ]);

      await _pumpDiscoveryPage(tester, harness: harness);

      await tester.longPress(find.text('Office laptop'));
      await _pumpForUi(tester);

      expect(find.text('Rename device'), findsOneWidget);
      expect(find.text('Add to friends'), findsOneWidget);

      await tester.tap(find.text('Rename device'));
      await _pumpForUi(tester);

      expect(find.text('Name is bound to device MAC address.'), findsOneWidget);
    },
  );

  testWidgets(
    'DiscoveryPage side menu keeps the video-link surface reachable as container actions',
    (tester) async {
      _registerWidgetCleanup(tester);
      await _pumpDiscoveryPage(tester, harness: harness, isBoundaryReady: true);

      await _openMenu(tester);
      await _pumpForUi(tester, frames: 16);

      expect(
        find.byKey(const Key('discovery-menu-action-files')),
        findsOneWidget,
      );
      await tester.dragUntilVisible(
        find.text('Web server for video'),
        find.byType(ListView).last,
        const Offset(0, -240),
      );
      await _pumpForUi(tester, frames: 8);
      expect(find.text('Web server for video'), findsOneWidget);
      expect(find.text('Video from shared files'), findsOneWidget);
      expect(find.byType(Switch), findsWidgets);
    },
  );
}

Future<void> _pumpDiscoveryPage(
  WidgetTester tester, {
  required TestDiscoveryControllerHarness harness,
  bool isBoundaryReady = false,
  TargetPlatform? platform,
}) async {
  final desktopWindowService = TrackingDesktopWindowService();
  final transferStorageService = StubTransferStorageService(
    rootDirectory: harness.databaseHarness.rootDirectory,
  );

  await tester.pumpWidget(
    MaterialApp(
      theme: platform == null ? null : ThemeData(platform: platform),
      home: DiscoveryPage(
        controller: harness.controller,
        readModel: harness.readModel,
        configuredDiscoveryTargetsStore:
            harness.configuredDiscoveryTargetsStore,
        remoteShareBrowser: harness.remoteShareBrowser,
        sharedCacheMaintenanceBoundary: harness.sharedCacheMaintenanceBoundary,
        videoLinkSessionBoundary: harness.videoLinkSessionBoundary,
        sharedCacheCatalog: harness.sharedCacheCatalog,
        sharedCacheIndexStore: harness.sharedCacheIndexStore,
        previewCacheOwner: harness.previewCacheOwner,
        transferSessionCoordinator: harness.transferSessionCoordinator,
        downloadHistoryBoundary: harness.downloadHistoryBoundary,
        clipboardHistoryStore: harness.clipboardHistoryStore,
        remoteClipboardProjectionStore: harness.remoteClipboardProjectionStore,
        desktopWindowService: desktopWindowService,
        transferStorageService: transferStorageService,
        createNearbyTransferSessionStore:
            harness.createNearbyTransferSessionStore,
        isBoundaryReady: isBoundaryReady,
      ),
    ),
  );
  await tester.pump();
  await _pumpForUi(tester, frames: 20);
}

Future<void> _openMenu(WidgetTester tester) async {
  await tester.tap(find.byTooltip('Menu'));
  await _pumpForUi(tester);
}

Future<void> _closeCurrentRoute(WidgetTester tester, Finder anchor) async {
  final context = tester.element(anchor.first);
  Navigator.of(context).pop();
  await _pumpForUi(tester);
}

Future<void> _pumpForUi(WidgetTester tester, {int frames = 12}) async {
  for (var i = 0; i < frames; i += 1) {
    await tester.pump(const Duration(milliseconds: 50));
  }
}

void _registerWidgetCleanup(WidgetTester tester) {
  addTearDown(() async {
    await tester.pumpWidget(const SizedBox.shrink());
    await _pumpForUi(tester);
  });
}

class StubTransferStorageService extends TransferStorageService {
  StubTransferStorageService({required this.rootDirectory});

  final Directory rootDirectory;

  @override
  Future<Directory> resolveReceiveDirectory({
    String appFolderName = 'Landa',
  }) async {
    final directory = Directory(p.join(rootDirectory.path, 'incoming'));
    await directory.create(recursive: true);
    return directory;
  }

  @override
  Future<Directory?> resolveAndroidPublicDownloadsDirectory() async {
    return null;
  }
}
