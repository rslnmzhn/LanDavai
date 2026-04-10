import 'dart:async';

import 'package:flutter/material.dart';

import '../../clipboard/application/clipboard_history_store.dart';
import '../../clipboard/application/clipboard_source_scope_store.dart';
import '../../clipboard/application/remote_clipboard_projection_store.dart';
import '../../clipboard/presentation/clipboard_sheet.dart';
import '../../history/application/download_history_boundary.dart';
import '../../settings/presentation/app_settings_sheet.dart';
import '../application/configured_discovery_targets_store.dart';
import '../application/discovery_controller.dart';
import '../application/discovery_read_model.dart';
import 'discovery_friends_sheet.dart';
import 'discovery_history_sheet.dart';
import '../../../core/utils/desktop_window_service.dart';

class DiscoveryDestinationPageScaffold extends StatelessWidget {
  const DiscoveryDestinationPageScaffold({
    required this.child,
    this.title,
    super.key,
  });

  final String? title;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: title == null ? AppBar() : AppBar(title: Text(title!)),
      body: child,
    );
  }
}

class DiscoveryMenuPage extends StatelessWidget {
  const DiscoveryMenuPage({required this.child, super.key});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return DiscoveryDestinationPageScaffold(title: 'Menu', child: child);
  }
}

class DiscoveryFriendsPage extends StatelessWidget {
  const DiscoveryFriendsPage({
    required this.controller,
    required this.readModel,
    super.key,
  });

  final DiscoveryController controller;
  final DiscoveryReadModel readModel;

  @override
  Widget build(BuildContext context) {
    return DefaultTabController(
      length: 2,
      child: DiscoveryDestinationPageScaffold(
        child: DiscoveryFriendsSheet(
          controller: controller,
          readModel: readModel,
        ),
      ),
    );
  }
}

class DiscoveryHistoryPage extends StatelessWidget {
  const DiscoveryHistoryPage({
    required this.downloadHistoryBoundary,
    required this.onOpenPath,
    super.key,
  });

  final DownloadHistoryBoundary downloadHistoryBoundary;
  final Future<void> Function(String path) onOpenPath;

  @override
  Widget build(BuildContext context) {
    return DiscoveryDestinationPageScaffold(
      child: DiscoveryHistorySheet(
        downloadHistoryBoundary: downloadHistoryBoundary,
        onOpenPath: onOpenPath,
      ),
    );
  }
}

class DiscoveryClipboardPage extends StatefulWidget {
  const DiscoveryClipboardPage({
    required this.controller,
    required this.readModel,
    required this.clipboardHistoryStore,
    required this.remoteClipboardProjectionStore,
    super.key,
  });

  final DiscoveryController controller;
  final DiscoveryReadModel readModel;
  final ClipboardHistoryStore clipboardHistoryStore;
  final RemoteClipboardProjectionStore remoteClipboardProjectionStore;

  @override
  State<DiscoveryClipboardPage> createState() => _DiscoveryClipboardPageState();
}

class _DiscoveryClipboardPageState extends State<DiscoveryClipboardPage> {
  late final ClipboardSourceScopeStore _clipboardSourceScopeStore;

  @override
  void initState() {
    super.initState();
    _clipboardSourceScopeStore = ClipboardSourceScopeStore();
  }

  @override
  void dispose() {
    _clipboardSourceScopeStore.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return DiscoveryDestinationPageScaffold(
      child: ClipboardSheet(
        controller: widget.controller,
        readModel: widget.readModel,
        clipboardHistoryStore: widget.clipboardHistoryStore,
        remoteClipboardProjectionStore: widget.remoteClipboardProjectionStore,
        clipboardSourceScopeStore: _clipboardSourceScopeStore,
      ),
    );
  }
}

class DiscoverySettingsPage extends StatelessWidget {
  const DiscoverySettingsPage({
    required this.controller,
    required this.readModel,
    required this.configuredDiscoveryTargetsStore,
    required this.desktopWindowService,
    super.key,
  });

  final DiscoveryController controller;
  final DiscoveryReadModel readModel;
  final ConfiguredDiscoveryTargetsStore configuredDiscoveryTargetsStore;
  final DesktopWindowService desktopWindowService;

  @override
  Widget build(BuildContext context) {
    return DiscoveryDestinationPageScaffold(
      child: AnimatedBuilder(
        animation: Listenable.merge(<Listenable>[
          controller,
          readModel,
          configuredDiscoveryTargetsStore,
        ]),
        builder: (context, _) {
          return AppSettingsSheet(
            settings: readModel.settings,
            configuredDiscoveryTargets: configuredDiscoveryTargetsStore.targets,
            configuredTargetValidator:
                configuredDiscoveryTargetsStore.validationErrorFor,
            onAddConfiguredDiscoveryTarget:
                configuredDiscoveryTargetsStore.addTarget,
            onRemoveConfiguredDiscoveryTarget:
                configuredDiscoveryTargetsStore.removeTarget,
            onBackgroundIntervalChanged: (interval) {
              unawaited(controller.updateBackgroundScanInterval(interval));
            },
            onDownloadAttemptNotificationsChanged: (enabled) {
              unawaited(
                controller.setDownloadAttemptNotificationsEnabled(enabled),
              );
            },
            onUseStandardAppDownloadFolderChanged: (enabled) {
              unawaited(controller.setUseStandardAppDownloadFolder(enabled));
            },
            onMinimizeToTrayChanged: (enabled) {
              unawaited(controller.setMinimizeToTrayOnClose(enabled));
              unawaited(desktopWindowService.setMinimizeToTrayEnabled(enabled));
            },
            onLeftHandedModeChanged: (enabled) {
              unawaited(controller.setLeftHandedMode(enabled));
            },
            onVideoLinkPasswordChanged: (value) {
              unawaited(controller.setVideoLinkPassword(value));
            },
            onPreviewCacheMaxSizeGbChanged: (value) {
              unawaited(controller.setPreviewCacheMaxSizeGb(value));
            },
            onPreviewCacheMaxAgeDaysChanged: (value) {
              unawaited(controller.setPreviewCacheMaxAgeDays(value));
            },
            onClipboardHistoryMaxEntriesChanged: (value) {
              unawaited(controller.setClipboardHistoryMaxEntries(value));
            },
            onRecacheParallelWorkersChanged: (value) {
              unawaited(controller.setRecacheParallelWorkers(value));
            },
          );
        },
      ),
    );
  }
}
