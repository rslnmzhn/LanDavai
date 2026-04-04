import 'package:flutter/material.dart';

import '../../../app/theme/app_colors.dart';
import '../../../app/theme/app_spacing.dart';
import '../../../core/widgets/horizontal_chip_row.dart';
import '../data/nearby_transfer_transport_adapter.dart';

class NearbyTransferDeviceListWidget extends StatelessWidget {
  const NearbyTransferDeviceListWidget({
    required this.devices,
    this.selectedDeviceId,
    this.onSelectDevice,
    this.onRefresh,
    super.key,
  });

  final List<NearbyTransferCandidateDevice> devices;
  final String? selectedDeviceId;
  final ValueChanged<NearbyTransferCandidateDevice>? onSelectDevice;
  final Future<void> Function()? onRefresh;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Text(
              'Устройства рядом',
              style: Theme.of(context).textTheme.titleSmall,
            ),
            const Spacer(),
            if (onRefresh != null)
              IconButton(
                tooltip: 'Обновить список',
                onPressed: onRefresh == null ? null : () => onRefresh!(),
                icon: const Icon(Icons.refresh_rounded),
              ),
          ],
        ),
        if (devices.isEmpty)
          Text(
            'Подходящие устройства пока не видны.',
            style: Theme.of(
              context,
            ).textTheme.bodySmall?.copyWith(color: AppColors.textSecondary),
          )
        else
          HorizontalChipRow(
            scrollKey: const Key('nearby-transfer-device-chip-row'),
            spacing: AppSpacing.xs,
            children: [
              for (final device in devices)
                ChoiceChip(
                  label: Text(device.displayName),
                  selected: selectedDeviceId == device.id,
                  onSelected: onSelectDevice == null
                      ? null
                      : (_) => onSelectDevice!(device),
                ),
            ],
          ),
      ],
    );
  }
}
