import 'dart:async';
import 'dart:io';

import '../core/storage/app_database.dart';
import '../core/utils/app_notification_service.dart';
import '../core/utils/desktop_window_service.dart';
import '../core/utils/path_opener.dart';
import '../features/clipboard/data/clipboard_capture_service.dart';
import '../features/clipboard/data/clipboard_history_repository.dart';
import '../features/discovery/application/discovery_controller.dart';
import '../features/discovery/application/discovery_read_model.dart';
import '../features/discovery/application/device_registry.dart';
import '../features/discovery/application/internet_peer_endpoint_store.dart';
import '../features/discovery/application/trusted_lan_peer_store.dart';
import '../features/discovery/data/device_alias_repository.dart';
import '../features/discovery/data/friend_repository.dart';
import '../features/discovery/data/lan_discovery_service.dart';
import '../features/discovery/data/network_host_scanner.dart';
import '../features/discovery/presentation/discovery_page.dart';
import '../features/history/data/transfer_history_repository.dart';
import '../features/settings/application/settings_store.dart';
import '../features/settings/data/app_settings_repository.dart';
import '../features/transfer/data/file_hash_service.dart';
import '../features/transfer/data/file_transfer_service.dart';
import '../features/transfer/data/shared_folder_cache_repository.dart';
import '../features/transfer/data/transfer_storage_service.dart';
import '../features/transfer/data/video_link_share_service.dart';
import 'package:flutter/widgets.dart';

class DiscoveryPageEntry extends StatefulWidget {
  const DiscoveryPageEntry({
    super.key,
    this.controller,
    this.readModel,
    this.desktopWindowService,
    this.transferStorageService,
    this.autoStartController = true,
  }) : assert(
         controller == null || readModel != null,
         'DiscoveryPageEntry requires readModel when controller is injected.',
       );

  final DiscoveryController? controller;
  final DiscoveryReadModel? readModel;
  final DesktopWindowService? desktopWindowService;
  final TransferStorageService? transferStorageService;
  final bool autoStartController;

  @override
  State<DiscoveryPageEntry> createState() => _DiscoveryPageEntryState();
}

class _DiscoveryPageEntryState extends State<DiscoveryPageEntry> {
  late final DiscoveryController _controller;
  late final DiscoveryReadModel _readModel;
  late final DesktopWindowService _desktopWindowService;
  late final TransferStorageService _transferStorageService;
  late final bool _ownsController;
  late final bool _ownsReadModel;
  bool _isBoundaryReady = false;

  @override
  void initState() {
    super.initState();
    _transferStorageService =
        widget.transferStorageService ?? TransferStorageService();
    if (widget.controller != null) {
      _controller = widget.controller!;
      _readModel = widget.readModel!;
      _ownsController = false;
      _ownsReadModel = false;
    } else {
      final boundary = _buildDiscoveryBoundary();
      _controller = boundary.controller;
      _readModel = boundary.readModel;
      _ownsController = true;
      _ownsReadModel = true;
    }
    _desktopWindowService =
        widget.desktopWindowService ?? DesktopWindowService();

    if (widget.autoStartController) {
      unawaited(_initializeBoundary());
    }
  }

  @override
  void dispose() {
    if (_ownsReadModel) {
      _readModel.dispose();
    }
    if (_ownsController) {
      _controller.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return DiscoveryPage(
      controller: _controller,
      readModel: _readModel,
      desktopWindowService: _desktopWindowService,
      transferStorageService: _transferStorageService,
      isBoundaryReady: _isBoundaryReady,
    );
  }

  Future<void> _initializeBoundary() async {
    await _controller.start();
    await _desktopWindowService.setMinimizeToTrayEnabled(
      _readModel.settings.minimizeToTrayOnClose,
    );
    if (!mounted) {
      return;
    }
    setState(() {
      _isBoundaryReady = true;
    });
  }

  _DiscoveryBoundary _buildDiscoveryBoundary() {
    final database = AppDatabase.instance;
    final deviceAliasRepository = DeviceAliasRepository(database: database);
    final friendRepository = FriendRepository(database: database);
    final settingsRepository = AppSettingsRepository(database: database);
    final settingsStore = SettingsStore(
      appSettingsRepository: settingsRepository,
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
    final controller = DiscoveryController(
      deviceRegistry: deviceRegistry,
      internetPeerEndpointStore: internetPeerEndpointStore,
      trustedLanPeerStore: trustedLanPeerStore,
      friendRepository: friendRepository,
      settingsStore: settingsStore,
      appNotificationService: AppNotificationService.instance,
      transferHistoryRepository: TransferHistoryRepository(database: database),
      clipboardHistoryRepository: ClipboardHistoryRepository(
        database: database,
      ),
      clipboardCaptureService: ClipboardCaptureService(),
      sharedFolderCacheRepository: SharedFolderCacheRepository(
        database: database,
      ),
      fileHashService: FileHashService(),
      fileTransferService: FileTransferService(),
      transferStorageService: _transferStorageService,
      videoLinkShareService: VideoLinkShareService(),
      pathOpener: PathOpener(),
      lanDiscoveryService: LanDiscoveryService(),
      networkHostScanner: NetworkHostScanner(
        allowTcpFallback: Platform.isAndroid,
      ),
    );
    final readModel = DiscoveryReadModel(
      legacyController: controller,
      deviceRegistry: deviceRegistry,
      internetPeerEndpointStore: internetPeerEndpointStore,
      trustedLanPeerStore: trustedLanPeerStore,
      settingsStore: settingsStore,
    );
    return _DiscoveryBoundary(controller: controller, readModel: readModel);
  }
}

class _DiscoveryBoundary {
  const _DiscoveryBoundary({required this.controller, required this.readModel});

  final DiscoveryController controller;
  final DiscoveryReadModel readModel;
}
