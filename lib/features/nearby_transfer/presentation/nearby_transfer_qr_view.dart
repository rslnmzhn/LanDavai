import 'package:flutter/material.dart';
import 'package:qr_flutter/qr_flutter.dart';

import '../../../app/theme/app_colors.dart';
import '../../../app/theme/app_radius.dart';
import '../../../app/theme/app_spacing.dart';

class NearbyTransferQrView extends StatefulWidget {
  const NearbyTransferQrView({required this.payload, super.key});

  final String payload;

  @override
  State<NearbyTransferQrView> createState() => _NearbyTransferQrViewState();
}

class _NearbyTransferQrViewState extends State<NearbyTransferQrView>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: const Duration(seconds: 2),
  )..repeat();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 280,
      child: Stack(
        alignment: Alignment.center,
        children: [
          AnimatedBuilder(
            animation: _controller,
            builder: (context, _) {
              return Stack(
                alignment: Alignment.center,
                children: List<Widget>.generate(3, (index) {
                  final progress = (_controller.value + index * 0.2) % 1;
                  final size = 200 + progress * 70;
                  return Container(
                    height: size,
                    width: size,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      border: Border.all(
                        color: AppColors.brandPrimary.withValues(
                          alpha: (0.24 - progress * 0.2).clamp(0.04, 0.24),
                        ),
                      ),
                    ),
                  );
                }),
              );
            },
          ),
          Container(
            padding: const EdgeInsets.all(AppSpacing.md),
            decoration: BoxDecoration(
              color: AppColors.surface,
              borderRadius: BorderRadius.circular(AppRadius.xl),
              boxShadow: const [
                BoxShadow(
                  blurRadius: 28,
                  color: Color(0x14000000),
                  offset: Offset(0, 12),
                ),
              ],
            ),
            child: Stack(
              alignment: Alignment.center,
              children: [
                QrImageView(
                  key: const Key('nearby-transfer-qr-image'),
                  data: widget.payload,
                  backgroundColor: Colors.white,
                  size: 200,
                ),
                Container(
                  height: 42,
                  width: 42,
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(AppRadius.md),
                  ),
                  padding: const EdgeInsets.all(AppSpacing.xxs),
                  child: Image.asset('assets/tray/landa_tray.png'),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
