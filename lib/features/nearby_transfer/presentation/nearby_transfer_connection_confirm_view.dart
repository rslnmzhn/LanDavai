import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

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
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (_store.role == NearbyTransferRole.send) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'nearby_transfer.verify_code_send'.tr(),
            style: Theme.of(context).textTheme.titleSmall,
          ),
          const SizedBox(height: AppSpacing.xs),
          Text(
            'nearby_transfer.verify_code_hint'.tr(),
            style: Theme.of(context).textTheme.bodySmall,
          ),
          const SizedBox(height: AppSpacing.sm),
          Text(
            _store.verificationCode.join(),
            style: Theme.of(
              context,
            ).textTheme.headlineSmall?.copyWith(fontFamily: 'JetBrainsMono'),
          ),
        ],
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'nearby_transfer.verify_code_receive'.tr(),
          style: Theme.of(context).textTheme.titleSmall,
        ),
        const SizedBox(height: AppSpacing.xs),
        Text(
          'nearby_transfer.verify_code_hint'.tr(),
          style: Theme.of(context).textTheme.bodySmall,
        ),
        const SizedBox(height: AppSpacing.sm),
        TextField(
          key: const Key('nearby-transfer-code-input'),
          controller: _controller,
          enabled: _store.canSubmitHandshakeCode,
          keyboardType: TextInputType.number,
          textInputAction: TextInputAction.done,
          maxLength: 2,
          inputFormatters: <TextInputFormatter>[
            FilteringTextInputFormatter.digitsOnly,
            LengthLimitingTextInputFormatter(2),
          ],
          decoration: InputDecoration(
            labelText: 'nearby_transfer.verify_code_input_label'.tr(),
            counterText: '',
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
            style: Theme.of(context).textTheme.bodySmall,
          ),
        ],
        const SizedBox(height: AppSpacing.sm),
        FilledButton(
          onPressed: _store.canSubmitHandshakeCode ? _submitCode : null,
          child: Text('nearby_transfer.verify_code_submit'.tr()),
        ),
      ],
    );
  }

  Future<void> _submitCode() async {
    await _store.submitHandshakeCode(_controller.text);
    if (!mounted) {
      return;
    }
    if (_store.phase == NearbyTransferSessionPhase.connected) {
      _controller.clear();
    }
  }
}
