import 'package:flutter/material.dart';
import 'package:mobile_scanner/mobile_scanner.dart';

import '../../../app/theme/app_colors.dart';
import '../../../app/theme/app_radius.dart';
import '../../../app/theme/app_spacing.dart';

class NearbyTransferScannerView extends StatelessWidget {
  const NearbyTransferScannerView({
    required this.liveScannerSupported,
    required this.onPayloadDetected,
    super.key,
  });

  final bool liveScannerSupported;
  final ValueChanged<String> onPayloadDetected;

  @override
  Widget build(BuildContext context) {
    if (!liveScannerSupported) {
      return Container(
        width: double.infinity,
        padding: const EdgeInsets.all(AppSpacing.md),
        decoration: BoxDecoration(
          color: AppColors.surface,
          borderRadius: BorderRadius.circular(AppRadius.lg),
          border: Border.all(color: AppColors.mutedBorder),
        ),
        child: Text(
          'Сканирование QR на этом устройстве недоступно. Используйте список устройств ниже.',
          style: Theme.of(context).textTheme.bodySmall,
        ),
      );
    }

    return ClipRRect(
      borderRadius: BorderRadius.circular(AppRadius.lg),
      child: SizedBox(
        height: 220,
        child: MobileScanner(
          onDetect: (capture) {
            final value = capture.barcodes
                .map((barcode) => barcode.rawValue)
                .whereType<String>()
                .firstWhere((raw) => raw.trim().isNotEmpty, orElse: () => '');
            if (value.isEmpty) {
              return;
            }
            onPayloadDetected(value);
          },
        ),
      ),
    );
  }
}
