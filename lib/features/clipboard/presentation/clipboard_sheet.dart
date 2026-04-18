import 'dart:async';

import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../app/theme/app_spacing.dart';
import '../application/clipboard_history_store.dart';
import '../application/clipboard_source_scope_store.dart';
import '../application/remote_clipboard_projection_store.dart';
import '../domain/clipboard_entry.dart';
import 'clipboard_preview_dialog.dart';
import 'clipboard_source_selector.dart';
import 'clipboard_sheet_list.dart';
import 'clipboard_sheet_preview.dart';
import '../../discovery/application/discovery_controller.dart';
import '../../discovery/application/discovery_read_model.dart';
import '../../discovery/domain/discovered_device.dart';

class ClipboardSheet extends StatefulWidget {
  const ClipboardSheet({
    required this.controller,
    required this.readModel,
    required this.clipboardHistoryStore,
    required this.remoteClipboardProjectionStore,
    required this.clipboardSourceScopeStore,
    super.key,
  });

  final DiscoveryController controller;
  final DiscoveryReadModel readModel;
  final ClipboardHistoryStore clipboardHistoryStore;
  final RemoteClipboardProjectionStore remoteClipboardProjectionStore;
  final ClipboardSourceScopeStore clipboardSourceScopeStore;

  @override
  State<ClipboardSheet> createState() => _ClipboardSheetState();
}

class _ClipboardSheetState extends State<ClipboardSheet> {
  @override
  void initState() {
    super.initState();
    widget.readModel.addListener(_handleAvailableRemoteDevicesChanged);
    _handleAvailableRemoteDevicesChanged();
  }

  @override
  void didUpdateWidget(covariant ClipboardSheet oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.readModel != widget.readModel) {
      oldWidget.readModel.removeListener(_handleAvailableRemoteDevicesChanged);
      widget.readModel.addListener(_handleAvailableRemoteDevicesChanged);
    }
    _handleAvailableRemoteDevicesChanged();
  }

  @override
  void dispose() {
    widget.readModel.removeListener(_handleAvailableRemoteDevicesChanged);
    super.dispose();
  }

  List<DiscoveredDevice> get _availableRemoteDevices {
    return widget.readModel.remoteClipboardDevices;
  }

  DiscoveredDevice? get _selectedRemoteDevice {
    final selectedRemoteIp = widget.clipboardSourceScopeStore.selectedRemoteIp;
    if (selectedRemoteIp == null) {
      return null;
    }
    for (final device in _availableRemoteDevices) {
      if (device.ip == selectedRemoteIp) {
        return device;
      }
    }
    return null;
  }

  void _handleAvailableRemoteDevicesChanged() {
    widget.clipboardSourceScopeStore.syncAvailableRemoteIps(
      _availableRemoteDevices.map((device) => device.ip),
    );
  }

  Future<void> _copyRemoteText(String value) async {
    await Clipboard.setData(ClipboardData(text: value));
    if (!mounted) {
      return;
    }
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text('clipboard.copied'.tr())));
  }

  Future<void> _copyLocalEntry(ClipboardHistoryEntry entry) async {
    final errorMessage = await widget.clipboardHistoryStore
        .copyEntryToSystemClipboard(entry);
    if (!mounted) {
      return;
    }

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(errorMessage ?? 'clipboard.copied'.tr())),
    );
  }

  Future<void> _previewLocalEntry(ClipboardHistoryEntry entry) async {
    if (entry.type == ClipboardEntryType.text) {
      final text = entry.textValue;
      if (text == null || text.isEmpty) {
        return;
      }
      await showClipboardTextPreviewDialog(
        context: context,
        title: 'clipboard.text_title'.tr(),
        text: text,
      );
      return;
    }

    final imageProvider = buildClipboardFullImageProviderFromPath(
      entry.imagePath,
    );
    if (imageProvider == null) {
      if (!mounted) {
        return;
      }
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('clipboard.image_unavailable'.tr())),
      );
      return;
    }

    await showClipboardImagePreviewDialog(
      context: context,
      title: 'clipboard.image_title'.tr(),
      imageProvider: imageProvider,
    );
  }

  Future<void> _previewRemoteEntry(RemoteClipboardEntry entry) async {
    if (entry.type == ClipboardEntryType.text) {
      final text = entry.textValue;
      if (text == null || text.isEmpty) {
        return;
      }
      await showClipboardTextPreviewDialog(
        context: context,
        title: 'clipboard.remote_text_title'.tr(),
        text: text,
        note: 'clipboard.remote_text_note'.tr(),
      );
      return;
    }

    final bytes = entry.imageBytes;
    if (bytes == null || bytes.isEmpty) {
      if (!mounted) {
        return;
      }
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('clipboard.remote_image_unavailable'.tr())),
      );
      return;
    }

    await showClipboardImagePreviewDialog(
      context: context,
      title: 'clipboard.remote_image_title'.tr(),
      imageProvider: MemoryImage(bytes),
      note: 'clipboard.remote_image_note'.tr(),
    );
  }

  Future<void> _confirmAndDeleteLocalEntry(ClipboardHistoryEntry entry) async {
    final shouldDelete = await showDialog<bool>(
      context: context,
      builder: (context) {
        final message = entry.type == ClipboardEntryType.text
            ? 'clipboard.remove_history_text'.tr()
            : 'clipboard.remove_history_image'.tr();
        return AlertDialog(
          title: Text('clipboard.remove_history_title'.tr()),
          content: Text(message),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(false),
              child: Text('common.cancel'.tr()),
            ),
            FilledButton(
              onPressed: () => Navigator.of(context).pop(true),
              child: Text('clipboard.delete'.tr()),
            ),
          ],
        );
      },
    );
    if (shouldDelete != true) {
      return;
    }
    await widget.clipboardHistoryStore.deleteEntry(entry.id);
  }

  Future<void> _loadSelectedRemoteClipboard() async {
    final selectedRemoteDevice = _selectedRemoteDevice;
    if (selectedRemoteDevice == null || !selectedRemoteDevice.isTrusted) {
      return;
    }
    await widget.controller.requestRemoteClipboardHistory(selectedRemoteDevice);
  }

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: AnimatedBuilder(
        animation: Listenable.merge(<Listenable>[
          widget.clipboardHistoryStore,
          widget.remoteClipboardProjectionStore,
          widget.clipboardSourceScopeStore,
          widget.readModel,
        ]),
        builder: (context, _) {
          final remoteDevices = _availableRemoteDevices;
          final selectedRemoteDevice = _selectedRemoteDevice;
          final isLocalSelected = selectedRemoteDevice == null;
          final selectedRemoteIp = selectedRemoteDevice?.ip;
          final localEntryPreviews = isLocalSelected
              ? buildLocalClipboardListPreviews(
                  widget.clipboardHistoryStore.entries,
                )
              : const <LocalClipboardListEntryPreview>[];
          final remoteEntryPreviews =
              !isLocalSelected && selectedRemoteIp != null
              ? buildRemoteClipboardListPreviews(
                  widget.remoteClipboardProjectionStore.entriesFor(
                    selectedRemoteIp,
                  ),
                )
              : const <RemoteClipboardListEntryPreview>[];
          final isRemoteLoading =
              selectedRemoteIp != null &&
              widget.remoteClipboardProjectionStore.isLoadingFor(
                selectedRemoteIp,
              );
          final remoteHasCachedEntries =
              selectedRemoteIp != null &&
              widget.remoteClipboardProjectionStore.hasEntriesFor(
                selectedRemoteIp,
              );
          final remoteLoadLabelKey = remoteHasCachedEntries
              ? 'common.refresh'
              : 'common.load';
          final emptyMessage = isLocalSelected
              ? 'clipboard.history_empty'.tr()
              : !selectedRemoteDevice.isTrusted
              ? 'clipboard.friend_required'.tr(
                  namedArgs: <String, String>{
                    'device': selectedRemoteDevice.displayName,
                  },
                )
              : 'clipboard.remote_empty'.tr(
                  namedArgs: <String, String>{
                    'device': selectedRemoteDevice.displayName,
                    'action': remoteLoadLabelKey.tr(),
                  },
                );

          return Padding(
            padding: const EdgeInsets.all(AppSpacing.md),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'clipboard.title'.tr(),
                  style: Theme.of(context).textTheme.titleLarge,
                ),
                const SizedBox(height: AppSpacing.sm),
                ClipboardSourceSelector(
                  remoteDevices: remoteDevices,
                  selectedSourceId:
                      widget.clipboardSourceScopeStore.selectedSourceId,
                  onSelectLocal: widget.clipboardSourceScopeStore.selectLocal,
                  onSelectRemote: (device) {
                    widget.clipboardSourceScopeStore.selectRemote(device.ip);
                  },
                ),
                if (!isLocalSelected) ...[
                  const SizedBox(height: AppSpacing.sm),
                  _RemoteClipboardScopeBanner(
                    device: selectedRemoteDevice,
                    isLoading: isRemoteLoading,
                    onLoad: selectedRemoteDevice.isTrusted && !isRemoteLoading
                        ? _loadSelectedRemoteClipboard
                        : null,
                    loadLabel: remoteLoadLabelKey.tr(),
                  ),
                ],
                const SizedBox(height: AppSpacing.sm),
                Expanded(
                  child: ClipboardSheetList(
                    isLocalScope: isLocalSelected,
                    localEntries: localEntryPreviews,
                    remoteEntries: remoteEntryPreviews,
                    isRemoteLoading: isRemoteLoading,
                    emptyMessage: emptyMessage,
                    onPreviewLocalEntry: _previewLocalEntry,
                    onPreviewRemoteEntry: _previewRemoteEntry,
                    onCopyLocalEntry: _copyLocalEntry,
                    onCopyRemoteText: _copyRemoteText,
                    onDeleteLocalEntry: _confirmAndDeleteLocalEntry,
                  ),
                ),
              ],
            ),
          );
        },
      ),
    );
  }
}

class _RemoteClipboardScopeBanner extends StatelessWidget {
  const _RemoteClipboardScopeBanner({
    required this.device,
    required this.isLoading,
    required this.loadLabel,
    this.onLoad,
  });

  final DiscoveredDevice device;
  final bool isLoading;
  final String loadLabel;
  final Future<void> Function()? onLoad;

  @override
  Widget build(BuildContext context) {
    final message = device.isTrusted
        ? 'clipboard.remote_viewing'.tr(
            namedArgs: <String, String>{'device': device.displayName},
          )
        : 'clipboard.remote_friends_only'.tr();
    return Row(
      children: [
        Expanded(
          child: Text(message, style: Theme.of(context).textTheme.bodySmall),
        ),
        const SizedBox(width: AppSpacing.sm),
        FilledButton(
          onPressed: onLoad == null ? null : () => unawaited(onLoad!()),
          child: Text(loadLabel),
        ),
      ],
    );
  }
}
