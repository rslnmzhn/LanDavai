import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../app/theme/app_colors.dart';
import '../../../app/theme/app_radius.dart';
import '../../../app/theme/app_spacing.dart';
import '../application/nearby_transfer_session_store.dart';
import '../data/nearby_transfer_transport_adapter.dart';

class NearbyTransferConnectionConfirmView extends StatefulWidget {
  const NearbyTransferConnectionConfirmView({required this.store, super.key});

  final NearbyTransferSessionStore store;

  @override
  State<NearbyTransferConnectionConfirmView> createState() =>
      _NearbyTransferConnectionConfirmViewState();
}

class _NearbyTransferConnectionConfirmViewState
    extends State<NearbyTransferConnectionConfirmView> {
  late final TextEditingController _controller;

  NearbyTransferSessionStore get _store => widget.store;

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController();
    _store.addListener(_handleStoreChanged);
  }

  @override
  void didUpdateWidget(covariant NearbyTransferConnectionConfirmView oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!identical(oldWidget.store, widget.store)) {
      oldWidget.store.removeListener(_handleStoreChanged);
      widget.store.addListener(_handleStoreChanged);
    }
  }

  void _handleStoreChanged() {
    if (mounted) {
      setState(() {});
    }
  }

  @override
  void dispose() {
    _store.removeListener(_handleStoreChanged);
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final peer = _store.peer;
    final remainingSeconds = _store.handshakeRemainingSeconds;
    final inlineError = _resolveInlineError();

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(AppSpacing.sm),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(AppRadius.lg),
        border: Border.all(color: AppColors.mutedBorder),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (peer != null) ...[
            Text(
              'nearby_transfer.peer_label'.tr(
                namedArgs: <String, String>{
                  'name': peer.displayName,
                  'host': peer.host,
                },
              ),
              style: Theme.of(
                context,
              ).textTheme.bodySmall?.copyWith(color: AppColors.brandPrimaryDark),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
            const SizedBox(height: AppSpacing.xxs),
          ],
          Text(
            _store.role == NearbyTransferRole.send
                ? 'nearby_transfer.verify_code_send'.tr()
                : 'nearby_transfer.verify_code_receive'.tr(),
            style: Theme.of(context).textTheme.titleSmall,
          ),
          const SizedBox(height: AppSpacing.xs),
          Wrap(
            spacing: AppSpacing.sm,
            runSpacing: AppSpacing.xxs,
            children: [
              Text(
                'nearby_transfer.verify_code_hint'.tr(),
                style: Theme.of(context).textTheme.bodySmall,
              ),
              if (remainingSeconds > 0)
                Text(
                  'nearby_transfer.verify_code_timer'.tr(
                    namedArgs: <String, String>{'seconds': '$remainingSeconds'},
                  ),
                  style: Theme.of(context).textTheme.labelMedium?.copyWith(
                    color: AppColors.brandPrimaryDark,
                  ),
                ),
            ],
          ),
          const SizedBox(height: AppSpacing.sm),
          if (_store.role == NearbyTransferRole.send)
            Container(
              padding: const EdgeInsets.symmetric(
                horizontal: AppSpacing.lg,
                vertical: AppSpacing.sm,
              ),
              decoration: BoxDecoration(
                color: AppColors.surfaceSoft,
                borderRadius: BorderRadius.circular(AppRadius.md),
                border: Border.all(color: AppColors.mutedBorder),
              ),
              child: Text(
                _store.verificationCode.join(),
                style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                  fontFamily: 'JetBrains Mono',
                  letterSpacing: 6,
                  color: AppColors.brandPrimaryDark,
                ),
              ),
            )
          else ...[
            TextField(
              key: const Key('nearby-transfer-code-input'),
              controller: _controller,
              enabled: _store.canSubmitHandshakeCode,
              keyboardType: TextInputType.number,
              textInputAction: TextInputAction.done,
              maxLength: 2,
              style: Theme.of(
                context,
              ).textTheme.titleLarge?.copyWith(fontFamily: 'JetBrains Mono'),
              inputFormatters: <TextInputFormatter>[
                FilteringTextInputFormatter.digitsOnly,
                LengthLimitingTextInputFormatter(2),
              ],
              decoration: InputDecoration(
                labelText: 'nearby_transfer.verify_code_input_label'.tr(),
                counterText: '',
                errorText: inlineError,
              ),
              onSubmitted: (_) => _submitCode(),
            ),
            if (_store.isHandshakeCoolingDown) ...[
              const SizedBox(height: AppSpacing.xs),
              Text(
                'nearby_transfer.verify_code_cooldown'.tr(
                  namedArgs: <String, String>{
                    'seconds': '${_store.handshakeCooldownRemainingSeconds}',
                  },
                ),
                style: Theme.of(
                  context,
                ).textTheme.bodySmall?.copyWith(color: AppColors.error),
              ),
            ],
            const SizedBox(height: AppSpacing.sm),
            SizedBox(
              width: double.infinity,
              child: FilledButton(
                onPressed: _store.canSubmitHandshakeCode ? _submitCode : null,
                child: Text('nearby_transfer.verify_code_submit'.tr()),
              ),
            ),
          ],
        ],
      ),
    );
  }

  String? _resolveInlineError() {
    if (!_store.bannerIsError) {
      return null;
    }
    return switch (_store.bannerCode) {
      NearbyTransferBannerCode.verifyCodeInvalid =>
        'nearby_transfer.verify_code_invalid'.tr(),
      NearbyTransferBannerCode.verifyCodeFormatError =>
        'nearby_transfer.verify_code_format_error'.tr(),
      _ => null,
    };
  }

  Future<void> _submitCode() async {
    await _store.submitHandshakeCode(_controller.text);
    if (!mounted) {
      return;
    }
    if (_store.phase == NearbyTransferSessionPhase.connected) {
      _controller.clear();
    } else if (_store.bannerCode == NearbyTransferBannerCode.verifyCodeInvalid) {
      _controller.selection = TextSelection(
        baseOffset: 0,
        extentOffset: _controller.text.length,
      );
    }
  }
}
