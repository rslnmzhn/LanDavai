import 'package:flutter/material.dart';

import '../../../app/theme/app_colors.dart';
import '../../../app/theme/app_spacing.dart';
import '../../../core/widgets/horizontal_chip_row.dart';
import '../application/clipboard_source_scope_store.dart';
import '../../discovery/domain/discovered_device.dart';

class ClipboardSourceSelector extends StatelessWidget {
  const ClipboardSourceSelector({
    required this.remoteDevices,
    required this.selectedSourceId,
    required this.onSelectLocal,
    required this.onSelectRemote,
    super.key,
  });

  final List<DiscoveredDevice> remoteDevices;
  final String selectedSourceId;
  final VoidCallback onSelectLocal;
  final void Function(DiscoveredDevice device) onSelectRemote;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('Clipboard source', style: Theme.of(context).textTheme.titleSmall),
        const SizedBox(height: AppSpacing.xs),
        HorizontalChipRow(
          scrollKey: const Key('clipboard-source-chip-row'),
          spacing: AppSpacing.xs,
          children: <Widget>[
            _ClipboardSourceChip(
              label: 'Current device',
              selected:
                  selectedSourceId == ClipboardSourceScopeStore.localSourceId,
              onSelected: onSelectLocal,
            ),
            for (final device in remoteDevices)
              _ClipboardSourceChip(
                label: device.displayName,
                selected:
                    selectedSourceId ==
                    ClipboardSourceScopeStore.remoteSourceId(device.ip),
                onSelected: () => onSelectRemote(device),
              ),
          ],
        ),
      ],
    );
  }
}

class _ClipboardSourceChip extends StatelessWidget {
  const _ClipboardSourceChip({
    required this.label,
    required this.selected,
    required this.onSelected,
  });

  final String label;
  final bool selected;
  final VoidCallback onSelected;

  @override
  Widget build(BuildContext context) {
    return ChoiceChip(
      label: Text(label),
      selected: selected,
      onSelected: (_) => onSelected(),
      selectedColor: AppColors.brandPrimary.withValues(alpha: 0.16),
      checkmarkColor: AppColors.brandPrimary,
      labelStyle: Theme.of(context).textTheme.labelLarge?.copyWith(
        color: selected ? AppColors.brandPrimary : AppColors.textSecondary,
      ),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(999),
        side: BorderSide(
          color: selected
              ? AppColors.brandPrimary.withValues(alpha: 0.32)
              : AppColors.mutedBorder,
        ),
      ),
      backgroundColor: AppColors.surface,
      materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
      visualDensity: VisualDensity.compact,
    );
  }
}
