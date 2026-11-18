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
  static const double _stageSize = 280;
  static const double _qrSize = 200;
  static const double _cardPadding = AppSpacing.md;
  static const double _cardSize = _qrSize + (_cardPadding * 2);

  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 2200),
  )..repeat();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: _stageSize,
      child: Center(
        child: SizedBox.square(
          key: const Key('nearby-transfer-qr-stage'),
          dimension: _stageSize,
          child: Stack(
            alignment: Alignment.center,
            children: [
              IgnorePointer(
                child: AnimatedBuilder(
                  animation: _controller,
                  builder: (context, _) {
                    return Stack(
                      alignment: Alignment.center,
                      children: List<Widget>.generate(3, (index) {
                        final progress = (_controller.value + index * 0.22) % 1;
                        final curved = Curves.easeOutCubic.transform(progress);
                        final scale = 0.96 + (curved * 0.34);
                        final alpha = (0.32 - curved * 0.26).clamp(0.0, 0.32);
                        return Transform.scale(
                          scale: scale,
                          child: Container(
                            key: Key('nearby-transfer-qr-pulse-$index'),
                            height: _cardSize + AppSpacing.sm,
                            width: _cardSize + AppSpacing.sm,
                            decoration: BoxDecoration(
                              borderRadius: BorderRadius.circular(
                                AppRadius.xl + AppSpacing.sm,
                              ),
                              border: Border.all(
                                width: 2,
                                color: AppColors.brandPrimary.withValues(
                                  alpha: alpha,
                                ),
                              ),
                              boxShadow: [
                                BoxShadow(
                                  blurRadius: 28,
                                  spreadRadius: curved * 6,
                                  color: AppColors.brandAccent.withValues(
                                    alpha: alpha * 0.55,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        );
                      }),
                    );
                  },
                ),
              ),
              DecoratedBox(
                decoration: BoxDecoration(
                  boxShadow: [
                    BoxShadow(
                      blurRadius: 42,
                      spreadRadius: 2,
                      color: AppColors.brandAccent.withValues(alpha: 0.28),
                    ),
                  ],
                ),
                child: Container(
                  key: const Key('nearby-transfer-qr-shell'),
                  padding: const EdgeInsets.all(_cardPadding),
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
                        size: _qrSize,
                      ),
                      Container(
                        height: 42,
                        width: 42,
                        decoration: BoxDecoration(
                          color: Colors.white,
                          borderRadius: BorderRadius.circular(AppRadius.md),
                          border: Border.all(color: AppColors.surfaceSoft),
                          boxShadow: [
                            BoxShadow(
                              blurRadius: 14,
                              color: AppColors.brandAccent.withValues(
                                alpha: 0.32,
                              ),
                            ),
                          ],
                        ),
                        padding: const EdgeInsets.all(AppSpacing.xxs),
                        child: Image.asset('assets/tray/landa_tray.png'),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
