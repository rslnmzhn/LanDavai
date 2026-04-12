import 'dart:io';

import 'package:flutter/foundation.dart';

import '../../core/storage/app_database.dart';
import '../../core/utils/app_notification_service.dart';
import '../../core/utils/desktop_window_service.dart';
import '../../core/utils/path_opener.dart';
import '../../features/clipboard/application/clipboard_history_store.dart';
import '../../features/clipboard/application/remote_clipboard_projection_store.dart';
import '../../features/clipboard/data/clipboard_capture_service.dart';
import '../../features/clipboard/data/clipboard_history_repository.dart';
import '../../features/discovery/application/discovery_controller.dart';
import '../../features/discovery/application/configured_discovery_targets_store.dart';
import '../../features/discovery/application/discovery_network_scope_store.dart';
import '../../features/discovery/application/discovery_read_model.dart';
import '../../features/discovery/application/device_registry.dart';
import '../../features/discovery/application/internet_peer_endpoint_store.dart';
import '../../features/discovery/application/local_peer_identity_store.dart';
import '../../features/discovery/application/remote_share_browser.dart';
import '../../features/discovery/application/remote_share_media_projection_boundary.dart';
import '../../features/discovery/application/shared_cache_maintenance_boundary.dart';
import '../../features/discovery/application/trusted_lan_peer_store.dart';
import '../../features/discovery/application/video_link_session_boundary.dart';
import '../../features/discovery/data/device_alias_repository.dart';
import '../../features/discovery/data/configured_discovery_targets_repository.dart';
import '../../features/discovery/data/discovery_network_interface_catalog.dart';
import '../../features/discovery/data/friend_repository.dart';
import '../../features/discovery/data/lan_discovery_service.dart';
import '../../features/discovery/data/lan_packet_codec.dart';
import '../../features/discovery/data/network_host_scanner.dart';
import '../../features/files/application/preview_cache_owner.dart';
import '../../features/history/application/download_history_boundary.dart';
import '../../features/history/data/transfer_history_repository.dart';
import '../../features/nearby_transfer/application/nearby_transfer_candidate_projection.dart';
import '../../features/nearby_transfer/application/nearby_transfer_availability_store.dart';
import '../../features/nearby_transfer/application/nearby_transfer_capability_service.dart';
import '../../features/nearby_transfer/application/nearby_transfer_handshake_service.dart';
import '../../features/nearby_transfer/application/nearby_transfer_mode_resolver.dart';
import '../../features/nearby_transfer/application/nearby_transfer_session_store.dart';
import '../../features/nearby_transfer/data/lan_nearby_transport_adapter.dart';
import '../../features/nearby_transfer/data/nearby_transfer_file_picker.dart';
import '../../features/nearby_transfer/data/nearby_transfer_storage_service.dart';
import '../../features/nearby_transfer/data/qr_payload_codec.dart';
import '../../features/nearby_transfer/data/wifi_direct_transport_adapter.dart';
import '../../features/settings/application/settings_store.dart';
import '../../features/settings/data/app_settings_repository.dart';
import '../../features/transfer/application/shared_cache_catalog.dart';
import '../../features/transfer/application/shared_cache_index_store.dart';
import '../../features/transfer/application/transfer_session_coordinator.dart';
import '../../features/transfer/data/file_hash_service.dart';
import '../../features/transfer/data/file_transfer_service.dart';
import '../../features/transfer/data/shared_download_diagnostic_log_store.dart';
import '../../features/transfer/data/shared_folder_cache_repository.dart';
import '../../features/transfer/data/thumbnail_cache_service.dart';
import '../../features/transfer/data/transfer_storage_service.dart';
import '../../features/transfer/data/video_link_share_service.dart';

class DiscoveryPageDependencies {
  const DiscoveryPageDependencies({
    required this.controller,
    required this.readModel,
    required this.configuredDiscoveryTargetsStore,
    required this.remoteShareBrowser,
    required this.sharedCacheMaintenanceBoundary,
    required this.videoLinkSessionBoundary,
    required this.sharedCacheCatalog,
    required this.sharedCacheIndexStore,
    required this.previewCacheOwner,
    required this.transferSessionCoordinator,
    required this.downloadHistoryBoundary,
    required this.clipboardHistoryStore,
    required this.remoteClipboardProjectionStore,
    required this.desktopWindowService,
    required this.transferStorageService,
    required this.createNearbyTransferSessionStore,
  });

  final DiscoveryController controller;
  final DiscoveryReadModel readModel;
  final ConfiguredDiscoveryTargetsStore configuredDiscoveryTargetsStore;
  final RemoteShareBrowser remoteShareBrowser;
  final SharedCacheMaintenanceBoundary sharedCacheMaintenanceBoundary;
  final VideoLinkSessionBoundary videoLinkSessionBoundary;
  final SharedCacheCatalog sharedCacheCatalog;
  final SharedCacheIndexStore sharedCacheIndexStore;
  final PreviewCacheOwner previewCacheOwner;
  final TransferSessionCoordinator transferSessionCoordinator;
  final DownloadHistoryBoundary downloadHistoryBoundary;
  final ClipboardHistoryStore clipboardHistoryStore;
  final RemoteClipboardProjectionStore remoteClipboardProjectionStore;
  final DesktopWindowService desktopWindowService;
  final TransferStorageService transferStorageService;
  final NearbyTransferSessionStore Function() createNearbyTransferSessionStore;
}

class DiscoveryCompositionResult {
  DiscoveryCompositionResult._({
    required this.pageDependencies,
    required VoidCallback disposeGraph,
    required bool disposeGraphOnDispose,
  }) : _disposeGraph = disposeGraph,
       _disposeGraphOnDispose = disposeGraphOnDispose;

  factory DiscoveryCompositionResult.injected({
    required DiscoveryPageDependencies pageDependencies,
  }) {
    return DiscoveryCompositionResult._(
      pageDependencies: pageDependencies,
      disposeGraph: () {},
      disposeGraphOnDispose: false,
    );
  }

  final DiscoveryPageDependencies pageDependencies;
  final VoidCallback _disposeGraph;
  final bool _disposeGraphOnDispose;
  bool _started = false;
  bool _disposed = false;

  Future<void> start() async {
    if (_started || _disposed) {
      return;
    }
    _started = true;
    await pageDependencies.controller.start();
    await pageDependencies.desktopWindowService.setMinimizeToTrayEnabled(
      pageDependencies.readModel.settings.minimizeToTrayOnClose,
    );
  }

  void dispose() {
    if (_disposed) {
      return;
    }
    _disposed = true;
    if (_disposeGraphOnDispose) {
      _disposeGraph();
    }
  }
}

class DiscoveryCompositionFactory {
  const DiscoveryCompositionFactory();

  DiscoveryCompositionResult create({
    DesktopWindowService? desktopWindowService,
    TransferStorageService? transferStorageService,
  }) {
    final database = AppDatabase.instance;
    final resolvedDesktopWindowService =
        desktopWindowService ?? DesktopWindowService();
    final resolvedTransferStorageService =
        transferStorageService ?? TransferStorageService();
    final deviceAliasRepository = DeviceAliasRepository(database: database);
    final friendRepository = FriendRepository(database: database);
    final localPeerIdentityStore = LocalPeerIdentityStore(database: database);
    final discoveryNetworkScopeStore = DiscoveryNetworkScopeStore(
      interfaceCatalog: SystemDiscoveryNetworkInterfaceCatalog(),
    );
    final settingsRepository = AppSettingsRepository(database: database);
    final settingsStore = SettingsStore(
      appSettingsRepository: settingsRepository,
    );
    final configuredDiscoveryTargetsStore = ConfiguredDiscoveryTargetsStore(
      repository: ConfiguredDiscoveryTargetsRepository(database: database),
    );
    final deviceRegistry = DeviceRegistry(
      deviceAliasRepository: deviceAliasRepository,
    );
    final internetPeerEndpointStore = InternetPeerEndpointStore(
      friendRepository: friendRepository,
    );
    final trustedLanPeerStore = TrustedLanPeerStore(
      deviceRegistry: deviceRegistry,
      deviceAliasRepository: deviceAliasRepository,
    );
    final thumbnailCacheService = ThumbnailCacheService(database: database);
    final sharedFolderCacheRepository = SharedFolderCacheRepository(
      database: database,
    );
    final sharedCacheIndexStore = SharedCacheIndexStore(
      database: database,
      thumbnailCacheService: thumbnailCacheService,
    );
    final sharedCacheCatalog = SharedCacheCatalog(
      sharedCacheRecordStore: sharedFolderCacheRepository,
      sharedCacheIndexStore: sharedCacheIndexStore,
    );
    final fileHashService = FileHashService();
    final previewCacheOwner = PreviewCacheOwner(
      sharedCacheThumbnailStore: thumbnailCacheService,
      sharedCacheIndexStore: sharedCacheIndexStore,
      fileHashService: fileHashService,
    );
    final nearbyTransferAvailabilityStore = NearbyTransferAvailabilityStore();
    final lanDiscoveryService = LanDiscoveryService(
      nearbyTransferPortProvider: () =>
          nearbyTransferAvailabilityStore.lanFallbackPort,
    );
    final fileTransferService = FileTransferService();
    final sharedDownloadDiagnosticLogStore = SharedDownloadDiagnosticLogStore();
    final transferHistoryRepository = TransferHistoryRepository(
      database: database,
    );
    final downloadHistoryBoundary = DownloadHistoryBoundary(
      transferHistoryRepository: transferHistoryRepository,
    );
    final clipboardHistoryRepository = ClipboardHistoryRepository(
      database: database,
    );
    final clipboardCaptureService = ClipboardCaptureService();
    final clipboardHistoryStore = ClipboardHistoryStore(
      clipboardHistoryRepository: clipboardHistoryRepository,
      clipboardCaptureService: clipboardCaptureService,
      transferStorageService: resolvedTransferStorageService,
    );
    final remoteClipboardProjectionStore = RemoteClipboardProjectionStore(
      fileHashService: fileHashService,
    );
    final remoteShareBrowser = RemoteShareBrowser(
      sharedCacheCatalog: sharedCacheCatalog,
    );
    final remoteShareMediaProjectionBoundary =
        RemoteShareMediaProjectionBoundary(
          remoteShareBrowser: remoteShareBrowser,
          sharedCacheCatalog: sharedCacheCatalog,
          sharedCacheIndexStore: sharedCacheIndexStore,
          sharedCacheThumbnailStore: thumbnailCacheService,
          fileHashService: fileHashService,
          lanDiscoveryService: lanDiscoveryService,
        );
    final videoLinkShareService = VideoLinkShareService();
    final nearbyTransferCapabilityService = NearbyTransferCapabilityService(
      wifiDirectSupported: false,
    );
    final nearbyTransferModeResolver = NearbyTransferModeResolver();
    final nearbyTransferHandshakeService = NearbyTransferHandshakeService();
    final nearbyTransferFilePicker = NearbyTransferFilePicker();
    final nearbyTransferStorageService = NearbyTransferStorageService(
      transferStorageService: resolvedTransferStorageService,
    );
    late final DiscoveryController controller;
    final transferSessionCoordinator = TransferSessionCoordinator(
      lanDiscoveryService: lanDiscoveryService,
      sharedCacheCatalog: sharedCacheCatalog,
      sharedCacheIndexStore: sharedCacheIndexStore,
      fileHashService: fileHashService,
      fileTransferService: fileTransferService,
      transferStorageService: resolvedTransferStorageService,
      downloadHistoryBoundary: downloadHistoryBoundary,
      previewCacheOwner: previewCacheOwner,
      appNotificationService: AppNotificationService.instance,
      settingsProvider: () => settingsStore.settings,
      localNameProvider: () => controller.localName,
      localDeviceMacProvider: () => controller.localDeviceMac,
      isTrustedSender: (normalizedMac) =>
          trustedLanPeerStore.isTrustedMac(normalizedMac),
      resolveRemoteOwnerMac:
          ({required String ownerIp, required String cacheId}) =>
              remoteShareBrowser.ownerMacForCache(
                ownerIp: ownerIp,
                cacheId: cacheId,
              ),
      applyRemoteShareAccessSnapshot:
          ({
            required String ownerIp,
            required String ownerName,
            required String ownerMacAddress,
            required List<SharedCatalogEntryItem> entries,
          }) => remoteShareBrowser.applyAccessSnapshot(
            ownerIp: ownerIp,
            ownerDisplayName: ownerName,
            ownerMacAddress: ownerMacAddress,
            entries: entries,
          ),
      sharedDownloadDiagnosticLogStore: sharedDownloadDiagnosticLogStore,
    );
    controller = DiscoveryController(
      deviceRegistry: deviceRegistry,
      internetPeerEndpointStore: internetPeerEndpointStore,
      trustedLanPeerStore: trustedLanPeerStore,
      localPeerIdentityStore: localPeerIdentityStore,
      discoveryNetworkScopeStore: discoveryNetworkScopeStore,
      settingsStore: settingsStore,
      configuredDiscoveryTargetsStore: configuredDiscoveryTargetsStore,
      appNotificationService: AppNotificationService.instance,
      transferHistoryRepository: transferHistoryRepository,
      downloadHistoryBoundary: downloadHistoryBoundary,
      clipboardHistoryRepository: clipboardHistoryRepository,
      clipboardCaptureService: clipboardCaptureService,
      clipboardHistoryStore: clipboardHistoryStore,
      remoteClipboardProjectionStore: remoteClipboardProjectionStore,
      remoteShareBrowser: remoteShareBrowser,
      remoteShareMediaProjectionBoundary: remoteShareMediaProjectionBoundary,
      sharedCacheCatalog: sharedCacheCatalog,
      sharedCacheIndexStore: sharedCacheIndexStore,
      fileHashService: fileHashService,
      fileTransferService: fileTransferService,
      transferStorageService: resolvedTransferStorageService,
      previewCacheOwner: previewCacheOwner,
      pathOpener: PathOpener(),
      nearbyTransferAvailabilityStore: nearbyTransferAvailabilityStore,
      lanDiscoveryService: lanDiscoveryService,
      networkHostScanner: NetworkHostScanner(
        allowTcpFallback: Platform.isAndroid,
      ),
      transferSessionCoordinator: transferSessionCoordinator,
    );
    final videoLinkSessionBoundary = VideoLinkSessionBoundary(
      videoLinkShareService: videoLinkShareService,
      hostAddressProvider: () => controller.localIp,
      hostChangeListenable: controller,
    );
    final readModel = DiscoveryReadModel(
      legacyController: controller,
      deviceRegistry: deviceRegistry,
      internetPeerEndpointStore: internetPeerEndpointStore,
      trustedLanPeerStore: trustedLanPeerStore,
      discoveryNetworkScopeStore: discoveryNetworkScopeStore,
      settingsStore: settingsStore,
      configuredDiscoveryTargetsStore: configuredDiscoveryTargetsStore,
    );
    final nearbyTransferCandidateProjection = NearbyTransferCandidateProjection(
      readModel: readModel,
    );
    final sharedCacheMaintenanceBoundary = SharedCacheMaintenanceBoundary(
      sharedCacheCatalog: sharedCacheCatalog,
      sharedCacheIndexStore: sharedCacheIndexStore,
      appNotificationService: AppNotificationService.instance,
      ownerMacAddressProvider: () => controller.localDeviceMac,
      settingsProvider: () => settingsStore.settings,
    );
    final pageDependencies = DiscoveryPageDependencies(
      controller: controller,
      readModel: readModel,
      configuredDiscoveryTargetsStore: configuredDiscoveryTargetsStore,
      remoteShareBrowser: remoteShareBrowser,
      sharedCacheMaintenanceBoundary: sharedCacheMaintenanceBoundary,
      videoLinkSessionBoundary: videoLinkSessionBoundary,
      sharedCacheCatalog: sharedCacheCatalog,
      sharedCacheIndexStore: sharedCacheIndexStore,
      previewCacheOwner: previewCacheOwner,
      transferSessionCoordinator: transferSessionCoordinator,
      downloadHistoryBoundary: downloadHistoryBoundary,
      clipboardHistoryStore: clipboardHistoryStore,
      remoteClipboardProjectionStore: remoteClipboardProjectionStore,
      desktopWindowService: resolvedDesktopWindowService,
      transferStorageService: resolvedTransferStorageService,
      createNearbyTransferSessionStore: () {
        return NearbyTransferSessionStore(
          capabilityService: nearbyTransferCapabilityService,
          modeResolver: nearbyTransferModeResolver,
          handshakeService: nearbyTransferHandshakeService,
          candidateProjection: nearbyTransferCandidateProjection,
          availabilityStore: nearbyTransferAvailabilityStore,
          qrCodec: const NearbyTransferQrCodec(),
          wifiDirectTransportAdapter: WifiDirectTransportAdapter(),
          lanNearbyTransportAdapter: LanNearbyTransportAdapter(
            fileHashService: fileHashService,
            fileTransferService: fileTransferService,
            storageService: nearbyTransferStorageService,
          ),
          filePicker: nearbyTransferFilePicker,
          localDeviceIdProvider: () => controller.localDeviceMac,
          localDeviceNameProvider: () => readModel.localName,
          localIpProvider: () => readModel.localIp,
        );
      },
    );

    return DiscoveryCompositionResult._(
      pageDependencies: pageDependencies,
      disposeGraphOnDispose: true,
      disposeGraph: () {
        readModel.dispose();
        discoveryNetworkScopeStore.dispose();
        remoteShareBrowser.dispose();
        previewCacheOwner.dispose();
        videoLinkSessionBoundary.dispose();
        controller.dispose();
      },
    );
  }
}
