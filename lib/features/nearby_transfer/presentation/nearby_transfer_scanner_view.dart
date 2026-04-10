import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:mobile_scanner/mobile_scanner.dart';

import '../../../app/theme/app_colors.dart';
import '../../../app/theme/app_radius.dart';
import '../../../app/theme/app_spacing.dart';

class NearbyTransferScannerView extends StatefulWidget {
  const NearbyTransferScannerView({
    required this.liveScannerSupported,
    required this.onPayloadDetected,
    this.previewBuilder,
    super.key,
  });

  final bool liveScannerSupported;
  final ValueChanged<String> onPayloadDetected;
  final Widget Function(ValueChanged<String> onDetected)? previewBuilder;

  @override
  State<NearbyTransferScannerView> createState() =>
      _NearbyTransferScannerViewState();
}

class _NearbyTransferScannerViewState extends State<NearbyTransferScannerView>
    with TickerProviderStateMixin {
  static const double _maxViewportSize = 320;
  static const double _frameInset = AppSpacing.lg;
  static const double _minFrameSize = 180;
  static const double _maxFrameSize = 224;
  static const Duration _feedbackHold = Duration(milliseconds: 900);

  late final AnimationController _scanLineController;
  late final AnimationController _feedbackController;

  Timer? _feedbackResetTimer;
  bool _detectionLocked = false;
  bool _showDetectionFeedback = false;

  @override
  void initState() {
    super.initState();
    _scanLineController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 2200),
    )..repeat();
    _feedbackController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 260),
    );
  }

  @override
  void dispose() {
    _feedbackResetTimer?.cancel();
    _scanLineController.dispose();
    _feedbackController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (!widget.liveScannerSupported) {
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

    return LayoutBuilder(
      builder: (context, constraints) {
        final viewportSize = _resolveViewportSize(constraints.biggest);
        return Center(
          child: ClipRRect(
            borderRadius: BorderRadius.circular(AppRadius.lg),
            child: SizedBox.square(
              key: const Key('nearby-transfer-scanner-stage'),
              dimension: viewportSize,
              child: LayoutBuilder(
                builder: (context, squareConstraints) {
                  final scanWindow = _buildScanWindow(
                    squareConstraints.biggest,
                  );
                  return Stack(
                    fit: StackFit.expand,
                    children: [
                      _buildPreview(scanWindow),
                      IgnorePointer(
                        child: NearbyTransferScannerOverlay(
                          scanWindow: scanWindow,
                          scanLineAnimation: _scanLineController,
                          feedbackAnimation: _feedbackController,
                          detectionActive: _showDetectionFeedback,
                        ),
                      ),
                    ],
                  );
                },
              ),
            ),
          ),
        );
      },
    );
  }

  double _resolveViewportSize(Size availableSize) {
    final bounded = math.min(availableSize.shortestSide, _maxViewportSize);
    return math.max(_minFrameSize + (_frameInset * 2), bounded);
  }

  Widget _buildPreview(Rect scanWindow) {
    final builder = widget.previewBuilder;
    if (builder != null) {
      return ColoredBox(
        color: Colors.black,
        child: builder(_handleDetectedPayload),
      );
    }
    return MobileScanner(
      scanWindow: scanWindow,
      fit: BoxFit.cover,
      overlayBuilder: (context, _) => const SizedBox.shrink(),
      onDetect: (capture) {
        final value = capture.barcodes
            .map((barcode) => barcode.rawValue)
            .whereType<String>()
            .firstWhere((raw) => raw.trim().isNotEmpty, orElse: () => '');
        if (value.isEmpty) {
          return;
        }
        _handleDetectedPayload(value);
      },
    );
  }

  Rect _buildScanWindow(Size size) {
    final squareSize = math.min(
      _maxFrameSize,
      math.max(_minFrameSize, size.shortestSide - (_frameInset * 2)),
    );
    return Rect.fromCenter(
      center: size.center(Offset.zero),
      width: squareSize,
      height: squareSize,
    );
  }

  void _handleDetectedPayload(String rawPayload) {
    if (_detectionLocked) {
      return;
    }
    _detectionLocked = true;
    _feedbackResetTimer?.cancel();
    setState(() {
      _showDetectionFeedback = true;
    });
    _feedbackController.forward(from: 0);
    widget.onPayloadDetected(rawPayload);
    _feedbackResetTimer = Timer(_feedbackHold, () {
      if (!mounted) {
        return;
      }
      _feedbackController.reverse();
      setState(() {
        _showDetectionFeedback = false;
      });
      _detectionLocked = false;
    });
  }
}

class NearbyTransferScannerOverlay extends StatelessWidget {
  const NearbyTransferScannerOverlay({
    required this.scanWindow,
    required this.scanLineAnimation,
    required this.feedbackAnimation,
    required this.detectionActive,
    super.key,
  });

  final Rect scanWindow;
  final Animation<double> scanLineAnimation;
  final Animation<double> feedbackAnimation;
  final bool detectionActive;

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        Positioned.fill(
          child: DecoratedBox(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [
                  Colors.black.withValues(alpha: 0.24),
                  Colors.black.withValues(alpha: 0.08),
                  Colors.black.withValues(alpha: 0.28),
                ],
              ),
            ),
          ),
        ),
        Positioned.fromRect(
          rect: scanWindow,
          child: Container(
            key: const Key('nearby-transfer-scanner-frame'),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(AppRadius.xl),
              border: Border.all(
                width: detectionActive ? 2.8 : 2.2,
                color: detectionActive
                    ? AppColors.success
                    : AppColors.brandAccent.withValues(alpha: 0.96),
              ),
              boxShadow: [
                BoxShadow(
                  blurRadius: detectionActive ? 24 : 18,
                  spreadRadius: detectionActive ? 2 : 0,
                  color:
                      (detectionActive
                              ? AppColors.success
                              : AppColors.brandPrimary)
                          .withValues(alpha: 0.24),
                ),
              ],
            ),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(AppRadius.xl - 2),
              child: Stack(
                fit: StackFit.expand,
                children: [
                  DecoratedBox(
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        begin: Alignment.topCenter,
                        end: Alignment.bottomCenter,
                        colors: [
                          Colors.white.withValues(alpha: 0.03),
                          Colors.transparent,
                          Colors.white.withValues(alpha: 0.04),
                        ],
                      ),
                    ),
                  ),
                  AnimatedBuilder(
                    animation: scanLineAnimation,
                    builder: (context, _) {
                      final travel = scanWindow.height - 18;
                      return Transform.translate(
                        offset: Offset(0, scanLineAnimation.value * travel),
                        child: Align(
                          alignment: Alignment.topCenter,
                          child: Container(
                            margin: const EdgeInsets.symmetric(
                              horizontal: AppSpacing.md,
                            ),
                            height: 18,
                            decoration: BoxDecoration(
                              gradient: LinearGradient(
                                colors: [
                                  AppColors.brandPrimary.withValues(alpha: 0),
                                  AppColors.brandPrimary.withValues(
                                    alpha: 0.78,
                                  ),
                                  AppColors.brandAccent.withValues(alpha: 0),
                                ],
                              ),
                            ),
                          ),
                        ),
                      );
                    },
                  ),
                  const _ScannerCornerAccent(alignment: Alignment.topLeft),
                  const _ScannerCornerAccent(alignment: Alignment.topRight),
                  const _ScannerCornerAccent(alignment: Alignment.bottomLeft),
                  const _ScannerCornerAccent(alignment: Alignment.bottomRight),
                  AnimatedBuilder(
                    animation: feedbackAnimation,
                    builder: (context, _) {
                      final scale = 0.84 + (feedbackAnimation.value * 0.18);
                      final opacity = detectionActive
                          ? (0.22 + (feedbackAnimation.value * 0.78))
                          : 0.0;
                      return IgnorePointer(
                        child: Center(
                          child: Opacity(
                            opacity: opacity,
                            child: Transform.scale(
                              scale: scale,
                              child: Container(
                                key: const Key(
                                  'nearby-transfer-scanner-detection-feedback',
                                ),
                                height: 72,
                                width: 72,
                                decoration: BoxDecoration(
                                  shape: BoxShape.circle,
                                  color: AppColors.success.withValues(
                                    alpha: 0.92,
                                  ),
                                  boxShadow: [
                                    BoxShadow(
                                      blurRadius: 24,
                                      spreadRadius: 3,
                                      color: AppColors.success.withValues(
                                        alpha: 0.34,
                                      ),
                                    ),
                                  ],
                                ),
                                child: const Icon(
                                  Icons.check_rounded,
                                  color: Colors.white,
                                  size: 34,
                                ),
                              ),
                            ),
                          ),
                        ),
                      );
                    },
                  ),
                ],
              ),
            ),
          ),
        ),
      ],
    );
  }
}

class _ScannerCornerAccent extends StatelessWidget {
  const _ScannerCornerAccent({required this.alignment});

  final Alignment alignment;

  bool get _isTop =>
      alignment == Alignment.topLeft || alignment == Alignment.topRight;
  bool get _isLeft =>
      alignment == Alignment.topLeft || alignment == Alignment.bottomLeft;

  @override
  Widget build(BuildContext context) {
    return Align(
      alignment: alignment,
      child: Container(
        width: 36,
        height: 36,
        margin: const EdgeInsets.all(AppSpacing.sm),
        decoration: BoxDecoration(
          border: Border(
            top: _isTop
                ? const BorderSide(color: AppColors.surface, width: 3)
                : BorderSide.none,
            bottom: !_isTop
                ? const BorderSide(color: AppColors.surface, width: 3)
                : BorderSide.none,
            left: _isLeft
                ? const BorderSide(color: AppColors.surface, width: 3)
                : BorderSide.none,
            right: !_isLeft
                ? const BorderSide(color: AppColors.surface, width: 3)
                : BorderSide.none,
          ),
          borderRadius: BorderRadius.only(
            topLeft: alignment == Alignment.topLeft
                ? const Radius.circular(AppRadius.md)
                : Radius.zero,
            topRight: alignment == Alignment.topRight
                ? const Radius.circular(AppRadius.md)
                : Radius.zero,
            bottomLeft: alignment == Alignment.bottomLeft
                ? const Radius.circular(AppRadius.md)
                : Radius.zero,
            bottomRight: alignment == Alignment.bottomRight
                ? const Radius.circular(AppRadius.md)
                : Radius.zero,
          ),
        ),
      ),
    );
  }
}
