import 'package:flutter/material.dart';

import '../../../app/theme/app_spacing.dart';
import '../domain/clipboard_entry.dart';
import 'clipboard_sheet_preview.dart';

class ClipboardHistoryPreviewRow extends StatelessWidget {
  const ClipboardHistoryPreviewRow({
    required this.leading,
    required this.metadata,
    required this.preview,
    required this.actions,
    this.onTap,
    super.key,
  });

  final Widget leading;
  final String metadata;
  final Widget preview;
  final List<Widget> actions;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final previewContent = Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(width: 56, height: 56, child: Center(child: leading)),
        const SizedBox(width: AppSpacing.sm),
        Expanded(
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: AppSpacing.xs),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(metadata, style: Theme.of(context).textTheme.bodyMedium),
                const SizedBox(height: 2),
                preview,
              ],
            ),
          ),
        ),
      ],
    );

    final content = Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(
          child: onTap == null
              ? previewContent
              : Material(
                  color: Colors.transparent,
                  child: InkWell(
                    borderRadius: BorderRadius.circular(16),
                    onTap: onTap,
                    child: Padding(
                      padding: const EdgeInsets.symmetric(
                        horizontal: AppSpacing.xs,
                        vertical: AppSpacing.xs,
                      ),
                      child: previewContent,
                    ),
                  ),
                ),
        ),
        if (actions.isNotEmpty) ...[
          const SizedBox(width: AppSpacing.xs),
          Padding(
            padding: const EdgeInsets.only(top: AppSpacing.xs),
            child: Row(mainAxisSize: MainAxisSize.min, children: actions),
          ),
        ],
      ],
    );

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: AppSpacing.xs),
      child: content,
    );
  }
}

class ClipboardSheetList extends StatelessWidget {
  const ClipboardSheetList({
    required this.isLocalScope,
    required this.localEntries,
    required this.remoteEntries,
    required this.isRemoteLoading,
    required this.emptyMessage,
    required this.onPreviewLocalEntry,
    required this.onPreviewRemoteEntry,
    required this.onCopyLocalEntry,
    required this.onCopyRemoteText,
    required this.onDeleteLocalEntry,
    super.key,
  });

  final bool isLocalScope;
  final List<LocalClipboardListEntryPreview> localEntries;
  final List<RemoteClipboardListEntryPreview> remoteEntries;
  final bool isRemoteLoading;
  final String emptyMessage;
  final Future<void> Function(ClipboardHistoryEntry entry) onPreviewLocalEntry;
  final Future<void> Function(RemoteClipboardEntry entry) onPreviewRemoteEntry;
  final Future<void> Function(ClipboardHistoryEntry entry) onCopyLocalEntry;
  final Future<void> Function(String value) onCopyRemoteText;
  final Future<void> Function(ClipboardHistoryEntry entry) onDeleteLocalEntry;

  @override
  Widget build(BuildContext context) {
    final visibleEntryCount = isLocalScope
        ? localEntries.length
        : remoteEntries.length;
    final hasEntries = visibleEntryCount > 0;
    final totalRowCount =
        (!isLocalScope && isRemoteLoading ? 1 : 0) +
        (hasEntries ? visibleEntryCount : 1);

    return ListView.builder(
      key: const Key('clipboard-sheet-list'),
      padding: EdgeInsets.zero,
      itemCount: totalRowCount,
      itemBuilder: (context, index) {
        if (!isLocalScope && isRemoteLoading && index == 0) {
          return const Padding(
            padding: EdgeInsets.only(bottom: AppSpacing.sm),
            child: LinearProgressIndicator(minHeight: 2),
          );
        }

        final contentIndex = !isLocalScope && isRemoteLoading
            ? index - 1
            : index;
        if (!hasEntries) {
          return _SectionMessage(
            message: emptyMessage,
            topPadding: AppSpacing.sm,
          );
        }

        if (isLocalScope) {
          final entry = localEntries[contentIndex];
          return _LocalEntryTile(
            key: ValueKey<String>('clipboard-local-entry-${entry.source.id}'),
            entry: entry,
            onPreviewEntry: onPreviewLocalEntry,
            onCopyEntry: onCopyLocalEntry,
            onDeleteEntry: onDeleteLocalEntry,
          );
        }

        final entry = remoteEntries[contentIndex];
        return _RemoteEntryTile(
          key: ValueKey<String>('clipboard-remote-entry-${entry.source.id}'),
          entry: entry,
          onPreviewEntry: onPreviewRemoteEntry,
          onCopyText: onCopyRemoteText,
        );
      },
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
    required this.onPreviewEntry,
    required this.onCopyEntry,
    required this.onDeleteEntry,
    super.key,
  });

  final LocalClipboardListEntryPreview entry;
  final Future<void> Function(ClipboardHistoryEntry entry) onPreviewEntry;
  final Future<void> Function(ClipboardHistoryEntry entry) onCopyEntry;
  final Future<void> Function(ClipboardHistoryEntry entry) onDeleteEntry;

  @override
  Widget build(BuildContext context) {
    final source = entry.source;
    if (source.type == ClipboardEntryType.text) {
      final text = source.textValue ?? '';
      return ClipboardHistoryPreviewRow(
        leading: const Icon(Icons.text_fields_rounded),
        metadata: entry.createdLabel,
        preview: Text(
          entry.previewText ?? '',
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
        ),
        onTap: () => onPreviewEntry(source),
        actions: <Widget>[
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
      );
    }

    return ClipboardHistoryPreviewRow(
      leading: _ClipboardThumbnail(provider: entry.imageProvider),
      metadata: entry.createdLabel,
      preview: Text(
        'Tap to preview image',
        style: Theme.of(context).textTheme.bodySmall,
      ),
      onTap: () => onPreviewEntry(source),
      actions: <Widget>[
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
    );
  }
}

class _RemoteEntryTile extends StatelessWidget {
  const _RemoteEntryTile({
    required this.entry,
    required this.onPreviewEntry,
    required this.onCopyText,
    super.key,
  });

  final RemoteClipboardListEntryPreview entry;
  final Future<void> Function(RemoteClipboardEntry entry) onPreviewEntry;
  final Future<void> Function(String value) onCopyText;

  @override
  Widget build(BuildContext context) {
    final source = entry.source;
    if (source.type == ClipboardEntryType.text) {
      final text = source.textValue ?? '';
      return ClipboardHistoryPreviewRow(
        leading: const Icon(Icons.text_fields_rounded),
        metadata: entry.createdLabel,
        preview: Text(
          entry.previewText ?? '',
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
        ),
        onTap: () => onPreviewEntry(source),
        actions: <Widget>[
          IconButton(
            tooltip: 'Copy text',
            icon: const Icon(Icons.copy_rounded),
            onPressed: text.isEmpty ? null : () => onCopyText(text),
          ),
        ],
      );
    }

    return ClipboardHistoryPreviewRow(
      leading: _ClipboardThumbnail(provider: entry.imageProvider),
      metadata: entry.createdLabel,
      preview: Text(
        'Preview only',
        style: Theme.of(context).textTheme.bodySmall,
      ),
      onTap: () => onPreviewEntry(source),
      actions: const <Widget>[],
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
