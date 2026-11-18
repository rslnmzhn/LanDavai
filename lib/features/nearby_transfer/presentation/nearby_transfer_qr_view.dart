import 'dart:math' as math;

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
  static const double _maxStageSize = 272;
  static const double _minStageSize = 180;
  static const double _cardPadding = AppSpacing.md;

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
    final screenHeight = MediaQuery.sizeOf(context).height;
    return LayoutBuilder(
      builder: (context, constraints) {
        final maxWidth = constraints.maxWidth.isFinite
            ? constraints.maxWidth
            : _maxStageSize;
        final heightBudget = math.max(_minStageSize, screenHeight * 0.46);
        final stageSize = math
            .min(_maxStageSize, math.min(maxWidth, heightBudget))
            .clamp(148.0, _maxStageSize);
        final cardSize = (stageSize - AppSpacing.xl * 1.5).clamp(124.0, 232.0);
        final qrSize = math.max(92.0, cardSize - (_cardPadding * 2));
        final logoSize = (qrSize * 0.19).clamp(28.0, 38.0);

        return SizedBox(
          height: stageSize,
          child: Center(
            child: SizedBox.square(
              key: const Key('nearby-transfer-qr-stage'),
              dimension: stageSize,
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
                            final progress =
                                (_controller.value + index * 0.22) % 1;
                            final curved = Curves.easeOutCubic.transform(
                              progress,
                            );
                            final scale = 0.96 + (curved * 0.22);
                            final alpha = (0.30 - curved * 0.25).clamp(
                              0.0,
                              0.30,
                            );
                            return Transform.scale(
                              scale: scale,
                              child: Container(
                                key: Key('nearby-transfer-qr-pulse-$index'),
                                height: cardSize + AppSpacing.xs,
                                width: cardSize + AppSpacing.xs,
                                decoration: BoxDecoration(
                                  borderRadius: BorderRadius.circular(
                                    AppRadius.xl,
                                  ),
                                  border: Border.all(
                                    width: 2,
                                    color: AppColors.brandPrimary.withValues(
                                      alpha: alpha,
                                    ),
                                  ),
                                  boxShadow: [
                                    BoxShadow(
                                      blurRadius: 20,
                                      spreadRadius: curved * 4,
                                      color: AppColors.brandAccent.withValues(
                                        alpha: alpha * 0.5,
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
                          blurRadius: 32,
                          spreadRadius: 2,
                          color: AppColors.brandAccent.withValues(alpha: 0.24),
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
                            blurRadius: 24,
                            color: AppColors.cardShadow,
                            offset: Offset(0, 10),
                          ),
                        ],
                      ),
                      child: Stack(
                        alignment: Alignment.center,
                        children: [
                          QrImageView(
                            key: const Key('nearby-transfer-qr-image'),
                            data: widget.payload,
                            errorCorrectionLevel: QrErrorCorrectLevel.H,
                            backgroundColor: AppColors.surface,
                            size: qrSize,
                          ),
                          Container(
                            height: logoSize,
                            width: logoSize,
                            decoration: BoxDecoration(
                              color: AppColors.surface,
                              borderRadius: BorderRadius.circular(AppRadius.sm),
                              border: Border.all(color: AppColors.surfaceSoft),
                              boxShadow: [
                                BoxShadow(
                                  blurRadius: 12,
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
      },
    );
  }
}
