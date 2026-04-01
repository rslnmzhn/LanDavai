import 'dart:async';

import 'package:flutter/widgets.dart';

import 'discovery/discovery_composition.dart';
import '../features/discovery/presentation/discovery_page.dart';

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

  @override
  void initState() {
    super.initState();
    _composition = widget.composition ?? widget.compositionFactory.create();
    if (widget.autoStartController) {
      unawaited(_initializeComposition());
    }
  }

  @override
  void dispose() {
    _composition.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final pageDependencies = _composition.pageDependencies;
    return DiscoveryPage(
      controller: pageDependencies.controller,
      readModel: pageDependencies.readModel,
      remoteShareBrowser: pageDependencies.remoteShareBrowser,
      sharedCacheMaintenanceBoundary:
          pageDependencies.sharedCacheMaintenanceBoundary,
      videoLinkSessionBoundary: pageDependencies.videoLinkSessionBoundary,
      sharedCacheCatalog: pageDependencies.sharedCacheCatalog,
      sharedCacheIndexStore: pageDependencies.sharedCacheIndexStore,
      previewCacheOwner: pageDependencies.previewCacheOwner,
      transferSessionCoordinator: pageDependencies.transferSessionCoordinator,
      downloadHistoryBoundary: pageDependencies.downloadHistoryBoundary,
      clipboardHistoryStore: pageDependencies.clipboardHistoryStore,
      remoteClipboardProjectionStore:
          pageDependencies.remoteClipboardProjectionStore,
      desktopWindowService: pageDependencies.desktopWindowService,
      transferStorageService: pageDependencies.transferStorageService,
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
  }
}
