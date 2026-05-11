import 'dart:async';

import 'package:flutter/widgets.dart';

import 'discovery/discovery_composition.dart';
import '../features/discovery/presentation/discovery_page.dart';
import 'router.dart';

class DiscoveryPageEntry extends StatefulWidget {
  const DiscoveryPageEntry({
    super.key,
    this.composition,
    this.compositionFactory = const DiscoveryCompositionFactory(),
    this.autoStartController = true,
  });

  final DiscoveryCompositionResult? composition;
  final DiscoveryCompositionFactory compositionFactory;
  final bool autoStartController;

  @override
  State<DiscoveryPageEntry> createState() => _DiscoveryPageEntryState();
}

class _DiscoveryPageEntryState extends State<DiscoveryPageEntry> {
  late final DiscoveryCompositionResult _composition;
  bool _isBoundaryReady = false;
  bool _shareRouteOpened = false;

  @override
  void initState() {
    super.initState();
    _composition = widget.composition ?? widget.compositionFactory.create();
    _composition.pageDependencies.shareReceiveBoundary.addListener(
      _handleShareBoundaryChanged,
    );
    if (widget.autoStartController) {
      unawaited(_initializeComposition());
    }
  }

  @override
  void dispose() {
    _composition.pageDependencies.shareReceiveBoundary.removeListener(
      _handleShareBoundaryChanged,
    );
    _composition.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final pageDependencies = _composition.pageDependencies;
    return DiscoveryPage(
      controller: pageDependencies.controller,
      readModel: pageDependencies.readModel,
      configuredDiscoveryTargetsStore:
          pageDependencies.configuredDiscoveryTargetsStore,
      remoteShareBrowser: pageDependencies.remoteShareBrowser,
      sharedCacheMaintenanceBoundary:
          pageDependencies.sharedCacheMaintenanceBoundary,
      videoLinkSessionBoundary: pageDependencies.videoLinkSessionBoundary,
      sharedCacheCatalog: pageDependencies.sharedCacheCatalog,
      sharedCacheIndexStore: pageDependencies.sharedCacheIndexStore,
      previewCacheOwner: pageDependencies.previewCacheOwner,
      transferSessionCoordinator: pageDependencies.transferSessionCoordinator,
      incomingTransferRequestBoundary:
          pageDependencies.incomingTransferRequestBoundary,
      remoteShareAccessSessionBoundary:
          pageDependencies.remoteShareAccessSessionBoundary,
      remoteFilePreviewTransferBoundary:
          pageDependencies.remoteFilePreviewTransferBoundary,
      transferCachePreparationBoundary:
          pageDependencies.transferCachePreparationBoundary,
      sharedDownloadBoundary: pageDependencies.sharedDownloadBoundary,
      downloadHistoryBoundary: pageDependencies.downloadHistoryBoundary,
      clipboardHistoryStore: pageDependencies.clipboardHistoryStore,
      remoteClipboardProjectionStore:
          pageDependencies.remoteClipboardProjectionStore,
      desktopWindowService: pageDependencies.desktopWindowService,
      transferStorageService: pageDependencies.transferStorageService,
      appUpdateBoundary: pageDependencies.appUpdateBoundary,
      createNearbyTransferSessionStore:
          pageDependencies.createNearbyTransferSessionStore,
      isBoundaryReady: _isBoundaryReady,
    );
  }

  Future<void> _initializeComposition() async {
    await _composition.start();
    if (!mounted) {
      return;
    }
    setState(() {
      _isBoundaryReady = true;
    });
    _openShareTargetIfNeeded();
  }

  void _handleShareBoundaryChanged() {
    _openShareTargetIfNeeded();
  }

  void _openShareTargetIfNeeded() {
    if (!mounted || _shareRouteOpened) {
      return;
    }
    final pageDependencies = _composition.pageDependencies;
    if (!pageDependencies.shareReceiveBoundary.hasPendingShare) {
      return;
    }

    _shareRouteOpened = true;
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      if (!mounted) {
        return;
      }
      await Navigator.of(context).pushNamed(
        AppRoutes.shareTarget,
        arguments: ShareTargetRouteArguments(
          shareReceiveBoundary: pageDependencies.shareReceiveBoundary,
          readModel: pageDependencies.readModel,
          transferSessionCoordinator:
              pageDependencies.transferSessionCoordinator,
        ),
      );
      if (mounted) {
        _shareRouteOpened = false;
        _openShareTargetIfNeeded();
      }
    });
  }
}
