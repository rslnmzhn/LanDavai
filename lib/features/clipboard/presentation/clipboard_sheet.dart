import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../app/theme/app_spacing.dart';
import '../application/clipboard_history_store.dart';
import '../../clipboard/domain/clipboard_entry.dart';
import '../../discovery/application/discovery_controller.dart';
import '../../discovery/application/discovery_read_model.dart';
import '../../discovery/domain/discovered_device.dart';

class ClipboardSheet extends StatefulWidget {
  const ClipboardSheet({
    required this.controller,
    required this.readModel,
    required this.clipboardHistoryStore,
    super.key,
  });

  final DiscoveryController controller;
  final DiscoveryReadModel readModel;
  final ClipboardHistoryStore clipboardHistoryStore;

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

  Future<void> _copyText(String value) async {
    await Clipboard.setData(ClipboardData(text: value));
    if (!mounted) {
      return;
    }
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(const SnackBar(content: Text('Copied to clipboard')));
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
          widget.controller,
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
              : widget.controller.remoteClipboardEntriesFor(_selectedRemoteIp!);

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
                  child: ListView(
                    children: [
                      Text(
                        'This device',
                        style: Theme.of(context).textTheme.titleMedium,
                      ),
                      const SizedBox(height: AppSpacing.xs),
                      if (localEntries.isEmpty)
                        const Text(
                          'History is empty. Copy text or image to start.',
                        )
                      else
                        ...localEntries.map(
                          (entry) => _LocalEntryTile(
                            entry: entry,
                            onCopyText: _copyText,
                            onDeleteEntry: _confirmAndDeleteLocalEntry,
                          ),
                        ),
                      const SizedBox(height: AppSpacing.md),
                      Text(
                        'Remote device',
                        style: Theme.of(context).textTheme.titleMedium,
                      ),
                      const SizedBox(height: AppSpacing.xs),
                      if (remoteDevices.isEmpty)
                        const Text(
                          'Add the device to Friends to view clipboard.',
                        )
                      else ...[
                        Row(
                          children: [
                            Expanded(
                              child: DropdownButtonFormField<String>(
                                key: ValueKey<String?>(_selectedRemoteIp),
                                initialValue: _selectedRemoteIp,
                                items: remoteDevices
                                    .map(
                                      (device) => DropdownMenuItem<String>(
                                        value: device.ip,
                                        child: Text(device.displayName),
                                      ),
                                    )
                                    .toList(growable: false),
                                onChanged: (next) {
                                  setState(() {
                                    _selectedRemoteIp = next;
                                  });
                                },
                                decoration: const InputDecoration(
                                  isDense: true,
                                  border: OutlineInputBorder(),
                                  labelText: 'Friend device',
                                ),
                              ),
                            ),
                            const SizedBox(width: AppSpacing.sm),
                            FilledButton(
                              onPressed:
                                  widget.controller.isLoadingRemoteClipboard ||
                                      _selectedRemoteIp == null
                                  ? null
                                  : () {
                                      final target = remoteDevices.firstWhere(
                                        (device) =>
                                            device.ip == _selectedRemoteIp,
                                      );
                                      widget.controller
                                          .requestRemoteClipboardHistory(
                                            target,
                                          );
                                    },
                              child: const Text('Load'),
                            ),
                          ],
                        ),
                        const SizedBox(height: AppSpacing.sm),
                        if (widget.controller.isLoadingRemoteClipboard)
                          const LinearProgressIndicator(minHeight: 2),
                        if (remoteEntries.isEmpty)
                          const Padding(
                            padding: EdgeInsets.only(top: AppSpacing.sm),
                            child: Text('No remote entries loaded.'),
                          )
                        else
                          ...remoteEntries.map(
                            (entry) => _RemoteEntryTile(
                              entry: entry,
                              onCopyText: _copyText,
                            ),
                          ),
                      ],
                    ],
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

class _LocalEntryTile extends StatelessWidget {
  const _LocalEntryTile({
    required this.entry,
    required this.onCopyText,
    required this.onDeleteEntry,
  });

  final ClipboardHistoryEntry entry;
  final Future<void> Function(String value) onCopyText;
  final Future<void> Function(ClipboardHistoryEntry entry) onDeleteEntry;

  @override
  Widget build(BuildContext context) {
    final created = entry.createdAt.toLocal().toIso8601String().replaceFirst(
      'T',
      ' ',
    );
    if (entry.type == ClipboardEntryType.text) {
      final text = entry.textValue ?? '';
      return ListTile(
        dense: true,
        leading: const Icon(Icons.text_fields_rounded),
        title: Text(text, maxLines: 3, overflow: TextOverflow.ellipsis),
        subtitle: Text(created),
        trailing: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            IconButton(
              tooltip: 'Copy',
              icon: const Icon(Icons.copy_rounded),
              onPressed: text.isEmpty ? null : () => onCopyText(text),
            ),
            IconButton(
              tooltip: 'Delete',
              icon: const Icon(Icons.delete_outline_rounded),
              onPressed: () => onDeleteEntry(entry),
            ),
          ],
        ),
      );
    }

    final imagePath = entry.imagePath;
    final imageFile = imagePath == null ? null : File(imagePath);
    return ListTile(
      dense: true,
      leading: SizedBox(
        width: 52,
        height: 52,
        child: imageFile == null || !imageFile.existsSync()
            ? const Icon(Icons.broken_image_outlined)
            : ClipRRect(
                borderRadius: BorderRadius.circular(8),
                child: Image.file(imageFile, fit: BoxFit.cover),
              ),
      ),
      title: const Text('Image from clipboard'),
      subtitle: Text(created),
      trailing: IconButton(
        tooltip: 'Delete',
        icon: const Icon(Icons.delete_outline_rounded),
        onPressed: () => onDeleteEntry(entry),
      ),
    );
  }
}

class _RemoteEntryTile extends StatelessWidget {
  const _RemoteEntryTile({required this.entry, required this.onCopyText});

  final RemoteClipboardEntry entry;
  final Future<void> Function(String value) onCopyText;

  @override
  Widget build(BuildContext context) {
    final created = entry.createdAt.toLocal().toIso8601String().replaceFirst(
      'T',
      ' ',
    );
    if (entry.type == ClipboardEntryType.text) {
      final text = entry.textValue ?? '';
      return ListTile(
        dense: true,
        leading: const Icon(Icons.text_fields_rounded),
        title: Text(text, maxLines: 3, overflow: TextOverflow.ellipsis),
        subtitle: Text(created),
        trailing: IconButton(
          tooltip: 'Copy',
          icon: const Icon(Icons.copy_rounded),
          onPressed: text.isEmpty ? null : () => onCopyText(text),
        ),
      );
    }

    final bytes = entry.imageBytes;
    return ListTile(
      dense: true,
      leading: SizedBox(
        width: 52,
        height: 52,
        child: bytes == null || bytes.isEmpty
            ? const Icon(Icons.broken_image_outlined)
            : ClipRRect(
                borderRadius: BorderRadius.circular(8),
                child: Image.memory(
                  Uint8List.fromList(bytes),
                  fit: BoxFit.cover,
                ),
              ),
      ),
      title: const Text('Image from remote clipboard'),
      subtitle: Text(created),
    );
  }
}
