import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:landa/app/duplicate_instance_notice_app.dart';
import 'package:landa/app/theme/app_theme.dart';
import 'package:landa/features/clipboard/application/clipboard_source_scope_store.dart';
import 'package:landa/features/clipboard/domain/clipboard_entry.dart';
import 'package:landa/features/clipboard/presentation/clipboard_sheet.dart';
import 'package:landa/features/discovery/data/lan_packet_codec_models.dart';
import 'package:landa/features/discovery/data/lan_protocol_events.dart';
import 'package:landa/features/discovery/domain/discovered_device.dart';
import 'package:landa/features/discovery/presentation/discovery_friends_sheet.dart';
import 'package:landa/features/discovery/presentation/discovery_history_sheet.dart';
import 'package:landa/features/discovery/presentation/discovery_page.dart';
import 'package:landa/features/discovery/presentation/remote_download_browser_page.dart';
import 'package:landa/features/files/application/files_feature_state_owner.dart';
import 'package:landa/features/files/presentation/file_explorer_page.dart';
import 'package:landa/features/history/domain/transfer_history_record.dart';
import 'package:landa/features/nearby_transfer/data/nearby_transfer_transport_adapter.dart';
import 'package:landa/features/nearby_transfer/presentation/nearby_transfer_entry_sheet.dart';
import 'package:landa/features/settings/presentation/app_settings_sheet.dart';
import 'package:landa/features/share_target/application/share_receive_boundary.dart';
import 'package:landa/features/share_target/presentation/share_target_page.dart';
import 'package:landa/features/transfer/data/transfer_storage_service.dart';

import 'test_support/fake_nearby_transfer.dart';
import 'test_support/localized_test_app.dart';
import 'test_support/test_discovery_controller.dart';

Future<void> _loadRealFonts() async {
  Future<void> loadFont(String family, String path) async {
    final file = File(path);
    if (!await file.exists()) return;
    final bytes = await file.readAsBytes();
    final loader = FontLoader(family);
    loader.addFont(Future<ByteData>.value(ByteData.sublistView(bytes)));
    await loader.load();
  }

  await loadFont('Manrope', 'assets/fonts/Manrope-Variable.ttf');
  await loadFont('JetBrains Mono', 'assets/fonts/JetBrainsMono-Variable.ttf');
  final flutterRoot = Platform.environment['FLUTTER_ROOT'];
  if (flutterRoot != null && flutterRoot.isNotEmpty) {
    await loadFont(
      'MaterialIcons',
      '$flutterRoot/bin/cache/artifacts/material_fonts/MaterialIcons-Regular.otf',
    );
  }
}

bool _hasAncestorRelation(Element a, Element b) {
  var found = false;
  a.visitAncestorElements((ancestor) {
    if (identical(ancestor, b)) {
      found = true;
      return false;
    }
    return true;
  });
  if (found) return true;
  b.visitAncestorElements((ancestor) {
    if (identical(ancestor, a)) {
      found = true;
      return false;
    }
    return true;
  });
  return found;
}

Rect? _visibleGlobalRect(Element element) {
  final ro = element.renderObject;
  if (ro is! RenderBox || !ro.hasSize || !ro.attached) return null;
  var rect = ro.localToGlobal(Offset.zero) & ro.size;
  if (rect.width <= 0 || rect.height <= 0) return null;
  element.visitAncestorElements((ancestor) {
    final aro = ancestor.renderObject;
    if (aro is RenderBox &&
        aro.hasSize &&
        (aro is RenderAbstractViewport ||
            aro is RenderClipRect ||
            aro is RenderClipRRect)) {
      final clipRect = aro.localToGlobal(Offset.zero) & aro.size;
      rect = rect.intersect(clipRect);
    }
    return true;
  });
  if (rect.width <= 0 || rect.height <= 0) return null;
  return rect;
}

List<String> _detectInteractiveOverlaps(WidgetTester tester) {
  final items = <({Element element, String desc, Rect rect})>[];
  for (final element in tester.allElements) {
    final widget = element.widget;
    final isControl =
        widget is IconButton ||
        widget is Checkbox ||
        widget is FilledButton ||
        widget is OutlinedButton ||
        widget is TextButton ||
        widget is Switch;
    if (!isControl) {
      continue;
    }
    final rect = _visibleGlobalRect(element);
    if (rect == null) continue;
    items.add((
      element: element,
      desc:
          '${widget.runtimeType}(key=${widget.key})@${rect.left.toStringAsFixed(0)},${rect.top.toStringAsFixed(0)} ${rect.width.toStringAsFixed(0)}x${rect.height.toStringAsFixed(0)}',
      rect: rect,
    ));
  }

  final overlaps = <String>[];
  for (var i = 0; i < items.length; i++) {
    for (var j = i + 1; j < items.length; j++) {
      if (_hasAncestorRelation(items[i].element, items[j].element)) {
        continue;
      }
      final inter = items[i].rect.intersect(items[j].rect);
      if (inter.width > 4 && inter.height > 4) {
        overlaps.add(
          'OVERLAP (${inter.width.toStringAsFixed(0)}x${inter.height.toStringAsFixed(0)}px): ${items[i].desc} <-> ${items[j].desc}',
        );
      }
    }
  }
  return overlaps;
}

void main() {
  const landaNetworkChannel = MethodChannel('landa/network');
  const outDir = '/tmp/landa_ui_audit';
  late TestDiscoveryControllerHarness harness;

  setUpAll(() async {
    await _loadRealFonts();
  });

  setUp(() async {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(landaNetworkChannel, (call) async => null);
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(SystemChannels.platform, (call) async => null);
    harness = await TestDiscoveryControllerHarness.create();
    await harness.clipboardHistoryStore.appendEntry(
      entry: ClipboardHistoryEntry(
        id: 'clip-1',
        type: ClipboardEntryType.text,
        contentHash: 'h1',
        textValue:
            'https://github.com/rslnmzhn/LanDavai — тестовая ссылка для передачи между устройствами',
        createdAt: DateTime(2026, 9, 12, 14, 2),
      ),
    );
    await harness.downloadHistoryBoundary.recordDownload(
      id: 'hist-1',
      peerName: 'Ноутбук Руслана (ThinkPad X1)',
      peerIp: '192.168.1.42',
      rootPath: '/home/user/Downloads/Landa',
      savedPaths: const <String>[
        '/home/user/Downloads/Landa/Архив_проекта_2026.zip',
      ],
      fileCount: 1,
      totalBytes: 256000000,
      status: TransferHistoryStatus.completed,
      createdAtMs: DateTime(2026, 9, 12, 13, 45).millisecondsSinceEpoch,
    );
  });

  tearDown(() async {
    await harness.dispose();
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(landaNetworkChannel, null);
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(SystemChannels.platform, null);
  });

  testWidgets('Full UI/Geometry/Overflow Audit across all screens & viewports', (
    tester,
  ) async {
    var currentScreen = 'init';
    final findings = <String>[];
    final originalOnError = FlutterError.onError;
    FlutterError.onError = (details) {
      findings.add(
        '[$currentScreen] FLUTTER_ERROR: ${details.exceptionAsString()}\n${details.context ?? ''}\n${details.informationCollector?.call().take(6).map((n) => n.toDescription()).join('\n') ?? ''}',
      );
    };
    addTearDown(() {
      FlutterError.onError = originalOnError;
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
      tester.view.resetViewInsets();
      tester.platformDispatcher.clearTextScaleFactorTestValue();
    });

    harness.controller.setTestDevices(<DiscoveredDevice>[
      DiscoveredDevice(
        ip: '192.168.1.42',
        macAddress: 'aa:bb:cc:dd:ee:42',
        deviceName: 'Ноутбук Руслана (ThinkPad X1 Carbon Gen 11)',
        operatingSystem: 'Linux',
        deviceCategory: DeviceCategory.pc,
        isTrusted: true,
        isAppDetected: true,
        isReachable: true,
        isNearbyTransferAvailable: true,
        nearbyTransferPort: 45321,
        lastSeen: DateTime(2026, 9, 12, 14, 0),
      ),
      DiscoveredDevice(
        ip: '192.168.1.88',
        macAddress: '11:22:33:44:55:88',
        deviceName: 'Samsung Galaxy S24 Ultra',
        operatingSystem: 'Android',
        deviceCategory: DeviceCategory.phone,
        isTrusted: false,
        isAppDetected: true,
        isReachable: true,
        lastSeen: DateTime(2026, 9, 12, 14, 1),
      ),
    ]);

    // Also add an incoming transfer request & friend request to test active request cards!
    harness.incomingTransferRequestBoundary.handleTransferRequestEvent(
      TransferRequestEvent(
        requestId: 'inc-req-1',
        senderIp: '192.168.1.88',
        senderName: 'Samsung Galaxy S24 Ultra (Гостевая сеть)',
        senderMacAddress: '11:22:33:44:55:88',
        sharedCacheId: '',
        sharedLabel: 'Фотографии из отпуска 2026',
        items: <TransferAnnouncementItem>[
          TransferAnnouncementItem(
            fileName: 'IMG_20260912_140522_HDR_Panorama.jpg',
            sizeBytes: 18450000,
            sha256: 'abc',
          ),
        ],
        observedAt: DateTime(2026, 9, 12, 14, 5),
      ),
    );

    final desktopWindowService = TrackingDesktopWindowService();
    final transferStorageService = TransferStorageService();

    Widget buildDiscovery() {
      return DiscoveryPage(
        controller: harness.controller,
        readModel: harness.readModel,
        configuredDiscoveryTargetsStore: harness.configuredDiscoveryTargetsStore,
        remoteShareBrowser: harness.remoteShareBrowser,
        sharedCacheMaintenanceBoundary: harness.sharedCacheMaintenanceBoundary,
        videoLinkSessionBoundary: harness.videoLinkSessionBoundary,
        sharedCacheCatalog: harness.sharedCacheCatalog,
        sharedCacheIndexStore: harness.sharedCacheIndexStore,
        previewCacheOwner: harness.previewCacheOwner,
        transferSessionCoordinator: harness.transferSessionCoordinator,
        incomingTransferRequestBoundary: harness.incomingTransferRequestBoundary,
        remoteShareAccessSessionBoundary:
            harness.remoteShareAccessSessionBoundary,
        remoteFilePreviewTransferBoundary:
            harness.remoteFilePreviewTransferBoundary,
        incomingTransferCompletionBoundary:
            harness.incomingTransferCompletionBoundary,
        transferCachePreparationBoundary:
            harness.transferCachePreparationBoundary,
        outgoingTransferSendBoundary: harness.outgoingTransferSendBoundary,
        sharedDownloadBoundary: harness.sharedDownloadBoundary,
        downloadHistoryBoundary: harness.downloadHistoryBoundary,
        clipboardHistoryStore: harness.clipboardHistoryStore,
        remoteClipboardProjectionStore: harness.remoteClipboardProjectionStore,
        desktopWindowService: desktopWindowService,
        transferStorageService: transferStorageService,
        appUpdateBoundary: harness.appUpdateBoundary,
        createNearbyTransferSessionStore:
            harness.createNearbyTransferSessionStore,
        isBoundaryReady: true,
      );
    }

    Future<void> checkScreen({
      required String name,
      required Size size,
      required Widget home,
      double textScale = 1.0,
      double keyboardHeight = 0,
    }) async {
      currentScreen = '$name (${size.width.toInt()}x${size.height.toInt()} ts=$textScale kb=$keyboardHeight)';
      final key = GlobalKey();
      tester.view.physicalSize = size * 2.0;
      tester.view.devicePixelRatio = 2.0;
      tester.view.viewInsets = FakeViewPadding(bottom: keyboardHeight * 2.0);
      tester.platformDispatcher.textScaleFactorTestValue = textScale;

      await tester.pumpWidget(
        RepaintBoundary(
          key: key,
          child: buildLocalizedTestApp(
            theme: AppTheme.light(),
            locale: const Locale('ru'),
            home: home,
          ),
        ),
      );
      for (var i = 0; i < 6; i++) {
        await tester.pump(const Duration(milliseconds: 50));
      }
      for (final ov in _detectInteractiveOverlaps(tester)) {
        findings.add('[$currentScreen] $ov');
      }
      if (Platform.environment['UPDATE_UI_AUDIT_SNAPSHOTS'] == '1') {
        await expectLater(
          find.byKey(key),
          matchesGoldenFile('$outDir/$name.png'),
        );
      }
    }

    // 1. DiscoveryPage narrow mobile + incoming transfer card
    await checkScreen(
      name: '01_discovery_mobile_320',
      size: const Size(320, 680),
      textScale: 1.2,
      home: buildDiscovery(),
    );

    // 2. DiscoveryPage desktop 900x620 (tight wide threshold) & 1100x760
    await checkScreen(
      name: '02_discovery_desktop_900',
      size: const Size(900, 620),
      home: buildDiscovery(),
    );

    // 3. NearbyTransferReceiveView: scanner stage on mobile & landscape
    final lanAdapter = FakeNearbyTransferTransportAdapter();
    final nearbyStore = buildTestNearbyTransferStore(
      readModel: harness.readModel,
      lanAdapter: lanAdapter,
    );
    await nearbyStore.prepareReceiveFlow();
    await checkScreen(
      name: '03a_nearby_receive_scanner_landscape',
      size: const Size(640, 360),
      home: NearbyTransferFlowPage(
        store: nearbyStore,
        initialStage: NearbyTransferEntryStage.receive,
      ),
    );

    // 3b. NearbyTransfer handshake confirm with keyboard open!
    lanAdapter.emit(
      const NearbyTransferConnectedEvent(
        peer: NearbyTransferPeerDevice(
          deviceId: 'peer-a',
          displayName: 'Ноутбук Руслана',
          host: '192.168.1.42',
        ),
        sessionId: 'session-a',
      ),
    );
    lanAdapter.emit(
      const NearbyTransferHandshakeOfferEvent(
        verificationCode: <String>['4', '7'],
      ),
    );
    await checkScreen(
      name: '03b_nearby_handshake_keyboard_360',
      size: const Size(360, 680),
      keyboardHeight: 280,
      home: NearbyTransferFlowPage(
        store: nearbyStore,
        initialStage: NearbyTransferEntryStage.receive,
      ),
    );

    // 3c. NearbyTransferReceiveView with offer
    lanAdapter.emit(const NearbyTransferHandshakeAcceptedEvent());
    lanAdapter.emit(
      const NearbyTransferIncomingSelectionOfferedEvent(
        requestId: 'req-1',
        label: 'Документы и Фото 2026',
        roots: <NearbyTransferRemoteOfferNode>[
          NearbyTransferRemoteOfferNode(
            id: 'dir:trip',
            name: 'Поездка в горы 2026',
            relativePath: 'Поездка в горы 2026',
            kind: NearbyTransferRemoteOfferNodeKind.directory,
            sizeBytes: 15400000,
            previewKind: NearbyTransferRemotePreviewKind.none,
            children: <NearbyTransferRemoteOfferNode>[],
          ),
          NearbyTransferRemoteOfferNode(
            id: 'file:notes',
            name: 'очень_длинный_отчет_за_третий_квартал_2026_финал.txt',
            relativePath: 'очень_длинный_отчет_за_третий_квартал_2026_финал.txt',
            kind: NearbyTransferRemoteOfferNodeKind.file,
            sizeBytes: 4096,
            previewKind: NearbyTransferRemotePreviewKind.text,
          ),
        ],
      ),
    );
    await checkScreen(
      name: '03c_nearby_receive_offer_320',
      size: const Size(320, 680),
      textScale: 1.15,
      home: NearbyTransferFlowPage(
        store: nearbyStore,
        initialStage: NearbyTransferEntryStage.receive,
      ),
    );

    // 4. NearbyTransferSendView QR (mobile 320x640 & landscape 640x360)
    final sendAdapter = FakeNearbyTransferTransportAdapter();
    final sendStore = buildTestNearbyTransferStore(
      readModel: harness.readModel,
      lanAdapter: sendAdapter,
    );
    await sendStore.prepareSendFlow();
    await checkScreen(
      name: '04_nearby_send_qr_320',
      size: const Size(320, 640),
      textScale: 1.15,
      home: NearbyTransferFlowPage(
        store: sendStore,
        initialStage: NearbyTransferEntryStage.send,
      ),
    );

    // 5. AppSettingsSheet (both Network & Storage tabs on 320x680)
    await checkScreen(
      name: '05a_settings_network_320',
      size: const Size(320, 680),
      textScale: 1.15,
      home: Scaffold(
        appBar: AppBar(title: const Text('Настройки')),
        body: AppSettingsSheet(
          settings: harness.readModel.settings,
          appUpdateBoundary: harness.appUpdateBoundary,
          configuredDiscoveryTargets: const <String>['100.64.0.12', '10.8.0.4'],
          configuredTargetValidator: (_) => null,
          onAddConfiguredDiscoveryTarget: (_) async => true,
          onRemoveConfiguredDiscoveryTarget: (_) async {},
          onBackgroundIntervalChanged: (_) async {},
          onDownloadAttemptNotificationsChanged: (_) async {},
          onUseStandardAppDownloadFolderChanged: (_) async {},
          onMinimizeToTrayChanged: (_) async {},
          onLeftHandedModeChanged: (_) async {},
          onVideoLinkPasswordChanged: (_) async {},
          onPreviewCacheMaxSizeGbChanged: (_) async {},
          onPreviewCacheMaxAgeDaysChanged: (_) async {},
          onClipboardHistoryMaxEntriesChanged: (_) async {},
          onRecacheParallelWorkersChanged: (_) async {},
          onDebugLogRetainedLinesChanged: (_) async {},
          onShowLogs: () async => null,
          onOpenLogsFolder: () async => null,
        ),
      ),
    );
    // Audit all 4 tabs (Network, Interface, Storage & Logs, Access) in AppSettingsSheet
    for (var tabIndex = 1; tabIndex < 4; tabIndex++) {
      final tabFinder = find.byType(Tab).at(tabIndex);
      await tester.ensureVisible(tabFinder);
      await tester.pumpAndSettle();
      await tester.tap(tabFinder);
      for (var i = 0; i < 6; i++) {
        await tester.pump(const Duration(milliseconds: 50));
      }
      for (final ov in _detectInteractiveOverlaps(tester)) {
        findings.add('[05_settings_tab_${tabIndex}_320] $ov');
      }
    }

    // 6. ClipboardSheet (320x680)
    await checkScreen(
      name: '06_clipboard_sheet_320',
      size: const Size(320, 680),
      textScale: 1.2,
      home: Scaffold(
        appBar: AppBar(title: const Text('Буфер обмена')),
        body: ClipboardSheet(
          controller: harness.controller,
          readModel: harness.readModel,
          clipboardHistoryStore: harness.clipboardHistoryStore,
          remoteClipboardProjectionStore: harness.remoteClipboardProjectionStore,
          clipboardSourceScopeStore: ClipboardSourceScopeStore(),
        ),
      ),
    );

    // 7. RemoteDownloadBrowserPage (320x680)
    await checkScreen(
      name: '07_remote_download_320',
      size: const Size(320, 680),
      textScale: 1.2,
      home: RemoteDownloadBrowserPage(
        readModel: harness.readModel,
        remoteShareBrowser: harness.remoteShareBrowser,
        previewCacheOwner: harness.previewCacheOwner,
        transferSessionCoordinator: harness.transferSessionCoordinator,
        remoteFilePreviewTransferBoundary:
            harness.remoteFilePreviewTransferBoundary,
        remoteShareAccessSessionBoundary:
            harness.remoteShareAccessSessionBoundary,
        incomingTransferCompletionBoundary:
            harness.incomingTransferCompletionBoundary,
        transferCachePreparationBoundary:
            harness.transferCachePreparationBoundary,
        sharedDownloadBoundary: harness.sharedDownloadBoundary,
        useStandardAppDownloadFolder: true,
      ),
    );

    // 8. FriendsSheet & HistorySheet (320x680)
    await checkScreen(
      name: '08_friends_sheet_320',
      size: const Size(320, 680),
      textScale: 1.2,
      home: DefaultTabController(
        length: 2,
        child: Scaffold(
          body: DiscoveryFriendsSheet(
            controller: harness.controller,
            readModel: harness.readModel,
          ),
        ),
      ),
    );

    await checkScreen(
      name: '09_history_sheet_320',
      size: const Size(320, 680),
      textScale: 1.2,
      home: Scaffold(
        body: DiscoveryHistorySheet(
          downloadHistoryBoundary: harness.downloadHistoryBoundary,
          onOpenPath: (_) async {},
        ),
      ),
    );

    // 10. FileExplorerPage (320x680)
    final filesOwner = FilesFeatureStateOwner(roots: const []);
    await filesOwner.initialize();
    await checkScreen(
      name: '10_file_explorer_320',
      size: const Size(320, 680),
      textScale: 1.2,
      home: FileExplorerPage(
        owner: filesOwner,
        previewCacheOwner: harness.previewCacheOwner,
        sharedCacheMaintenanceBoundary: harness.sharedCacheMaintenanceBoundary,
      ),
    );
    filesOwner.dispose();

    // 11. ShareTargetPage (320x680)
    final shareBoundary = ShareReceiveBoundary(
      consumePendingSharedFiles: () async => const <String>[
        '/tmp/shared_document_very_long_filename_2026.pdf',
      ],
    );
    await shareBoundary.initialize();
    await checkScreen(
      name: '11_share_target_320',
      size: const Size(320, 680),
      textScale: 1.2,
      home: ShareTargetPage(
        shareReceiveBoundary: shareBoundary,
        readModel: harness.readModel,
        transferSessionCoordinator: harness.transferSessionCoordinator,
      ),
    );
    shareBoundary.dispose();

    // 12. DuplicateInstanceNoticeApp (320x600)
    await checkScreen(
      name: '12_duplicate_instance_320',
      size: const Size(320, 600),
      textScale: 1.2,
      home: const DuplicateInstanceNoticeApp(),
    );

    nearbyStore.dispose();
    sendStore.dispose();
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump();
    FlutterError.onError = originalOnError;

    // ignore: avoid_print
    print('=== AUDIT_FINDINGS_COUNT=${findings.length} ===');
    for (final f in findings) {
      // ignore: avoid_print
      print('FINDING:\n$f\n---');
    }
    expect(
      findings,
      isEmpty,
      reason: 'Expected zero RenderFlex overflows and zero overlapping controls across all 12 screens:\n${findings.join('\n\n')}',
    );
  });
}
