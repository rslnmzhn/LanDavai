import 'package:flutter/material.dart';

import '../../../app/theme/app_colors.dart';
import '../../../app/theme/app_spacing.dart';
import '../../../core/widgets/horizontal_chip_row.dart';
import '../application/discovery_network_scope_store.dart';
import '../application/discovery_read_model.dart';
import '../application/discovery_network_scope.dart';

class DiscoveryNetworkScopeSelector extends StatelessWidget {
  const DiscoveryNetworkScopeSelector({
    required this.readModel,
    required this.onSelectScope,
    super.key,
  });

  final DiscoveryReadModel readModel;
  final void Function(String scopeId) onSelectScope;

  @override
  Widget build(BuildContext context) {
    final ranges = readModel.availableNetworkRanges;
    if (ranges.isEmpty) {
      return const SizedBox.shrink();
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('Network scope', style: Theme.of(context).textTheme.titleSmall),
        const SizedBox(height: AppSpacing.xs),
        HorizontalChipRow(
          scrollKey: const Key('discovery-network-scope-chip-row'),
          spacing: AppSpacing.xs,
          children: [
            _ScopeChip(
              label: 'Все',
              selected:
                  readModel.selectedNetworkScopeId ==
                  DiscoveryNetworkScopeStore.allScopeId,
              onSelected: () =>
                  onSelectScope(DiscoveryNetworkScopeStore.allScopeId),
            ),
            for (final range in ranges)
              _ScopeChip(
                label: _labelForRange(range),
                selected: readModel.selectedNetworkScopeId == range.id,
                onSelected: () => onSelectScope(range.id),
              ),
          ],
        ),
      ],
    );
  }

  String _labelForRange(DiscoveryNetworkRange range) {
    final adapterNames = range.adapterNames;
    if (adapterNames.isEmpty) {
      return range.subnetCidr;
    }

    for (final adapterName in adapterNames) {
      final normalized = adapterName.toLowerCase();
      if (normalized.contains('tailscale')) {
        return 'Tailscale';
      }
      if (normalized.contains('zerotier')) {
        return 'ZeroTier';
      }
      if (normalized.contains('hamachi')) {
        return 'Hamachi';
      }
    }

    final firstAdapter = adapterNames.first.trim();
    return firstAdapter.isEmpty ? range.subnetCidr : firstAdapter;
  }
}

class _ScopeChip extends StatelessWidget {
  const _ScopeChip({
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
