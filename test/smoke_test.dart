import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

import 'package:landa/features/discovery/data/discovery_network_interface_catalog.dart';
import 'package:landa/features/discovery/domain/discovered_device.dart';
import 'package:landa/features/discovery/presentation/discovery_page.dart';
import 'package:landa/features/transfer/data/transfer_storage_service.dart';

import 'test_support/localized_test_app.dart';
import 'test_support/test_discovery_controller.dart';

void main() {
  const landaNetworkChannel = MethodChannel('landa/network');
  late TestDiscoveryControllerHarness harness;

  setUp(() async {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(landaNetworkChannel, (call) async => null);
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(SystemChannels.platform, (call) async {
          if (call.method == 'SystemSound.play') {
            return null;
          }
          return null;
        });
    harness = await TestDiscoveryControllerHarness.create();
    addTearDown(() async {
      await harness.dispose();
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(landaNetworkChannel, null);
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(SystemChannels.platform, null);
    });
  });

  testWidgets(
    'DiscoveryPage renders with injected dependencies and does not own controller disposal',
    (tester) async {
      _registerWidgetCleanup(tester);
      await _setStandardSurface(tester);
      await _pumpDiscoveryPage(tester, harness: harness);

      expect(tester.takeException(), isNull);
      expect(harness.controller.startCalls, 0);

      await tester.pumpWidget(const SizedBox.shrink());
      await _pumpForUi(tester);

      expect(harness.controller.disposeCalls, 0);
    },
  );

  testWidgets('DiscoveryPage keeps subnet scope tabs off the main surface', (
    tester,
  ) async {
    _registerWidgetCleanup(tester);
    await _setStandardSurface(tester);
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
    ]);

    await _pumpDiscoveryPage(tester, harness: harness);

    expect(
      find.byKey(const Key('discovery-network-scope-chip-row')),
      findsNothing,
    );
    expect(find.text('Network scope'), findsNothing);
    expect(find.text('Все'), findsNothing);
    expect(find.text('Office LAN'), findsNothing);
    expect(find.text('Tailscale'), findsNothing);
  });
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
    buildLocalizedTestApp(
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
  await tester.pumpAndSettle();
  await _pumpForUi(tester, frames: 20);
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

Future<void> _setStandardSurface(WidgetTester tester) async {
  tester.view.physicalSize = const Size(700, 1400);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
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
