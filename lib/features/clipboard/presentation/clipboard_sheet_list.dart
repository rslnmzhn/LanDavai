import 'package:flutter/material.dart';

import '../../../app/theme/app_spacing.dart';
import '../../discovery/domain/discovered_device.dart';
import '../domain/clipboard_entry.dart';
import 'clipboard_sheet_preview.dart';

class ClipboardSheetList extends StatelessWidget {
  const ClipboardSheetList({
    required this.localEntries,
    required this.remoteDevices,
    required this.selectedRemoteIp,
    required this.remoteEntries,
    required this.isRemoteLoading,
    required this.onRemoteDeviceChanged,
    required this.onLoadRemoteEntries,
    required this.onCopyLocalEntry,
    required this.onCopyRemoteText,
    required this.onDeleteLocalEntry,
    super.key,
  });

  final List<LocalClipboardListEntryPreview> localEntries;
  final List<DiscoveredDevice> remoteDevices;
  final String? selectedRemoteIp;
  final List<RemoteClipboardListEntryPreview> remoteEntries;
  final bool isRemoteLoading;
  final ValueChanged<String?> onRemoteDeviceChanged;
  final VoidCallback? onLoadRemoteEntries;
  final Future<void> Function(ClipboardHistoryEntry entry) onCopyLocalEntry;
  final Future<void> Function(String value) onCopyRemoteText;
  final Future<void> Function(ClipboardHistoryEntry entry) onDeleteLocalEntry;

  bool get _hasRemoteDevices => remoteDevices.isNotEmpty;

  @override
  Widget build(BuildContext context) {
    final localContentCount = localEntries.isEmpty ? 1 : localEntries.length;
    final remoteSectionCount = _remoteSectionCount();
    final totalRowCount = 1 + localContentCount + 1 + remoteSectionCount;

    return ListView.builder(
      key: const Key('clipboard-sheet-list'),
      padding: EdgeInsets.zero,
      itemCount: totalRowCount,
      itemBuilder: (context, index) {
        var cursor = 0;

        if (index == cursor) {
          return const _SectionHeader(title: 'This device');
        }
        cursor += 1;

        if (index < cursor + localContentCount) {
          if (localEntries.isEmpty) {
            return const _SectionMessage(
              message: 'History is empty. Copy text or image to start.',
            );
          }
          final entry = localEntries[index - cursor];
          return _LocalEntryTile(
            key: ValueKey<String>('clipboard-local-entry-${entry.source.id}'),
            entry: entry,
            onCopyEntry: onCopyLocalEntry,
            onDeleteEntry: onDeleteLocalEntry,
          );
        }
        cursor += localContentCount;

        if (index == cursor) {
          return const _SectionHeader(
            title: 'Remote device',
            topPadding: AppSpacing.md,
          );
        }
        cursor += 1;

        return _buildRemoteSectionRow(context, index - cursor);
      },
    );
  }

  int _remoteSectionCount() {
    if (!_hasRemoteDevices) {
      return 1;
    }
    final remoteContentCount = remoteEntries.isEmpty ? 1 : remoteEntries.length;
    return 1 + (isRemoteLoading ? 1 : 0) + remoteContentCount;
  }

  Widget _buildRemoteSectionRow(BuildContext context, int remoteIndex) {
    if (!_hasRemoteDevices) {
      return const _SectionMessage(
        message: 'Add the device to Friends to view clipboard.',
      );
    }

    if (remoteIndex == 0) {
      return Padding(
        padding: const EdgeInsets.only(bottom: AppSpacing.sm),
        child: Row(
          children: [
            Expanded(
              child: DropdownButtonFormField<String>(
                key: ValueKey<String?>(selectedRemoteIp),
                initialValue: selectedRemoteIp,
                items: remoteDevices
                    .map(
                      (device) => DropdownMenuItem<String>(
                        value: device.ip,
                        child: Text(device.displayName),
                      ),
                    )
                    .toList(growable: false),
                onChanged: onRemoteDeviceChanged,
                decoration: const InputDecoration(
                  isDense: true,
                  border: OutlineInputBorder(),
                  labelText: 'Friend device',
                ),
              ),
            ),
            const SizedBox(width: AppSpacing.sm),
            FilledButton(
              onPressed: onLoadRemoteEntries,
              child: const Text('Load'),
            ),
          ],
        ),
      );
    }

    var contentIndex = remoteIndex - 1;
    if (isRemoteLoading) {
      if (contentIndex == 0) {
        return const Padding(
          padding: EdgeInsets.only(bottom: AppSpacing.sm),
          child: LinearProgressIndicator(minHeight: 2),
        );
      }
      contentIndex -= 1;
    }

    if (remoteEntries.isEmpty) {
      return const _SectionMessage(
        message: 'No remote entries loaded.',
        topPadding: AppSpacing.sm,
      );
    }

    final entry = remoteEntries[contentIndex];
    return _RemoteEntryTile(
      key: ValueKey<String>('clipboard-remote-entry-${entry.source.id}'),
      entry: entry,
      onCopyText: onCopyRemoteText,
    );
  }
}

class _SectionHeader extends StatelessWidget {
  const _SectionHeader({required this.title, this.topPadding = 0});

  final String title;
  final double topPadding;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.only(top: topPadding, bottom: AppSpacing.xs),
      child: Text(title, style: Theme.of(context).textTheme.titleMedium),
    );
  }
}

class _SectionMessage extends StatelessWidget {
  const _SectionMessage({required this.message, this.topPadding = 0});

  final String message;
  final double topPadding;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.only(top: topPadding),
      child: Text(message),
    );
  }
}

class _LocalEntryTile extends StatelessWidget {
  const _LocalEntryTile({
    required this.entry,
    required this.onCopyEntry,
    required this.onDeleteEntry,
    super.key,
  });

  final LocalClipboardListEntryPreview entry;
  final Future<void> Function(ClipboardHistoryEntry entry) onCopyEntry;
  final Future<void> Function(ClipboardHistoryEntry entry) onDeleteEntry;

  @override
  Widget build(BuildContext context) {
    final source = entry.source;
    if (source.type == ClipboardEntryType.text) {
      final text = source.textValue ?? '';
      return ListTile(
        dense: true,
        leading: const Icon(Icons.text_fields_rounded),
        title: Text(
          entry.previewText ?? '',
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
        ),
        subtitle: Text(entry.createdLabel),
        trailing: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            IconButton(
              tooltip: 'Copy text',
              icon: const Icon(Icons.copy_rounded),
              onPressed: text.isEmpty ? null : () => onCopyEntry(source),
            ),
            IconButton(
              tooltip: 'Delete',
              icon: const Icon(Icons.delete_outline_rounded),
              onPressed: () => onDeleteEntry(source),
            ),
          ],
        ),
      );
    }

    return ListTile(
      dense: true,
      leading: _ClipboardThumbnail(provider: entry.imageProvider),
      title: const Text('Image from clipboard'),
      subtitle: Text(entry.createdLabel),
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          IconButton(
            tooltip: 'Copy image',
            icon: const Icon(Icons.copy_rounded),
            onPressed: () => onCopyEntry(source),
          ),
          IconButton(
            tooltip: 'Delete',
            icon: const Icon(Icons.delete_outline_rounded),
            onPressed: () => onDeleteEntry(source),
          ),
        ],
      ),
    );
  }
}

class _RemoteEntryTile extends StatelessWidget {
  const _RemoteEntryTile({
    required this.entry,
    required this.onCopyText,
    super.key,
  });

  final RemoteClipboardListEntryPreview entry;
  final Future<void> Function(String value) onCopyText;

  @override
  Widget build(BuildContext context) {
    final source = entry.source;
    if (source.type == ClipboardEntryType.text) {
      final text = source.textValue ?? '';
      return ListTile(
        dense: true,
        leading: const Icon(Icons.text_fields_rounded),
        title: Text(
          entry.previewText ?? '',
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
        ),
        subtitle: Text(entry.createdLabel),
        trailing: IconButton(
          tooltip: 'Copy text',
          icon: const Icon(Icons.copy_rounded),
          onPressed: text.isEmpty ? null : () => onCopyText(text),
        ),
      );
    }

    return ListTile(
      dense: true,
      leading: _ClipboardThumbnail(provider: entry.imageProvider),
      title: const Text('Image from remote clipboard'),
      subtitle: Text(entry.createdLabel),
    );
  }
}

class _ClipboardThumbnail extends StatelessWidget {
  const _ClipboardThumbnail({required this.provider});

  final ImageProvider<Object>? provider;

  @override
  Widget build(BuildContext context) {
    final child = provider == null
        ? const Icon(Icons.broken_image_outlined)
        : Image(
            image: provider!,
            fit: BoxFit.cover,
            filterQuality: FilterQuality.low,
            errorBuilder: (_, error, stackTrace) =>
                const Icon(Icons.broken_image_outlined),
          );

    return SizedBox(
      width: 52,
      height: 52,
      child: ClipRRect(borderRadius: BorderRadius.circular(8), child: child),
    );
  }
}
