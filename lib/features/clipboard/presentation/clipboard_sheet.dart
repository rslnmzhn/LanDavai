import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../app/theme/app_spacing.dart';
import '../application/clipboard_history_store.dart';
import '../application/remote_clipboard_projection_store.dart';
import '../domain/clipboard_entry.dart';
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
    super.key,
  });

  final DiscoveryController controller;
  final DiscoveryReadModel readModel;
  final ClipboardHistoryStore clipboardHistoryStore;
  final RemoteClipboardProjectionStore remoteClipboardProjectionStore;

  @override
  State<ClipboardSheet> createState() => _ClipboardSheetState();
}

class _ClipboardSheetState extends State<ClipboardSheet> {
  String? _selectedRemoteIp;

  @override
  void initState() {
    super.initState();
    final firstFriend = _availableRemoteDevices.isEmpty
        ? null
        : _availableRemoteDevices.first.ip;
    _selectedRemoteIp = firstFriend;
  }

  List<DiscoveredDevice> get _availableRemoteDevices {
    return widget.readModel.friendDevices
        .where((device) => device.isAppDetected)
        .toList(growable: false);
  }

  Future<void> _copyRemoteText(String value) async {
    await Clipboard.setData(ClipboardData(text: value));
    if (!mounted) {
      return;
    }
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(const SnackBar(content: Text('Copied to clipboard')));
  }

  Future<void> _copyLocalEntry(ClipboardHistoryEntry entry) async {
    final errorMessage = await widget.clipboardHistoryStore
        .copyEntryToSystemClipboard(entry);
    if (!mounted) {
      return;
    }

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(errorMessage ?? 'Copied to clipboard')),
    );
  }

  Future<void> _confirmAndDeleteLocalEntry(ClipboardHistoryEntry entry) async {
    final shouldDelete = await showDialog<bool>(
      context: context,
      builder: (context) {
        final message = entry.type == ClipboardEntryType.text
            ? 'Delete this text entry from history?'
            : 'Delete this image entry from history?';
        return AlertDialog(
          title: const Text('Remove from history'),
          content: Text(message),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(false),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () => Navigator.of(context).pop(true),
              child: const Text('Delete'),
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

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: AnimatedBuilder(
        animation: Listenable.merge(<Listenable>[
          widget.clipboardHistoryStore,
          widget.remoteClipboardProjectionStore,
          widget.readModel,
        ]),
        builder: (context, _) {
          final localEntries = widget.clipboardHistoryStore.entries;
          final remoteDevices = _availableRemoteDevices;
          if (_selectedRemoteIp != null &&
              remoteDevices.every((device) => device.ip != _selectedRemoteIp)) {
            _selectedRemoteIp = remoteDevices.isEmpty
                ? null
                : remoteDevices.first.ip;
          }
          final remoteEntries = _selectedRemoteIp == null
              ? const <RemoteClipboardEntry>[]
              : widget.remoteClipboardProjectionStore.entriesFor(
                  _selectedRemoteIp!,
                );
          final localEntryPreviews = buildLocalClipboardListPreviews(
            localEntries,
          );
          final remoteEntryPreviews = buildRemoteClipboardListPreviews(
            remoteEntries,
          );
          final isRemoteLoading =
              _selectedRemoteIp != null &&
              widget.remoteClipboardProjectionStore.isLoadingFor(
                _selectedRemoteIp!,
              );

          return Padding(
            padding: const EdgeInsets.all(AppSpacing.md),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Clipboard',
                  style: Theme.of(context).textTheme.titleLarge,
                ),
                const SizedBox(height: AppSpacing.sm),
                Expanded(
                  child: ClipboardSheetList(
                    localEntries: localEntryPreviews,
                    remoteDevices: remoteDevices,
                    selectedRemoteIp: _selectedRemoteIp,
                    remoteEntries: remoteEntryPreviews,
                    isRemoteLoading: isRemoteLoading,
                    onRemoteDeviceChanged: (next) {
                      setState(() {
                        _selectedRemoteIp = next;
                      });
                    },
                    onLoadRemoteEntries:
                        isRemoteLoading || _selectedRemoteIp == null
                        ? null
                        : () {
                            final target = remoteDevices.firstWhere(
                              (device) => device.ip == _selectedRemoteIp,
                            );
                            unawaited(
                              widget.controller.requestRemoteClipboardHistory(
                                target,
                              ),
                            );
                          },
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
