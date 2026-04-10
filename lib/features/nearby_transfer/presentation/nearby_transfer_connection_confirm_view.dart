import 'package:flutter/material.dart';

import '../../../app/theme/app_spacing.dart';
import '../application/nearby_transfer_session_store.dart';
import '../data/nearby_transfer_transport_adapter.dart';

class NearbyTransferConnectionConfirmView extends StatelessWidget {
  const NearbyTransferConnectionConfirmView({required this.store, super.key});

  final NearbyTransferSessionStore store;

  @override
  Widget build(BuildContext context) {
    final challenge = store.handshakeChallenge;
    if (store.role == NearbyTransferRole.send) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Попросите второе устройство подтвердить этот код:',
            style: Theme.of(context).textTheme.titleSmall,
          ),
          const SizedBox(height: AppSpacing.sm),
          Text(
            _formatVerificationCode(store.verificationCode),
            style: Theme.of(
              context,
            ).textTheme.headlineSmall?.copyWith(fontFamily: 'JetBrainsMono'),
          ),
        ],
      );
    }

    if (challenge == null) {
      return const SizedBox.shrink();
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Выберите совпадающий цифровой код',
          style: Theme.of(context).textTheme.titleSmall,
        ),
        const SizedBox(height: AppSpacing.sm),
        for (final choice in challenge.choices) ...[
          SizedBox(
            width: double.infinity,
            child: OutlinedButton(
              onPressed: () => store.selectHandshakeChoice(choice),
              child: Text(
                _formatVerificationCode(choice),
                style: Theme.of(
                  context,
                ).textTheme.titleMedium?.copyWith(fontFamily: 'JetBrainsMono'),
              ),
            ),
          ),
          const SizedBox(height: AppSpacing.xs),
        ],
      ],
    );
  }
}

String _formatVerificationCode(List<String> digits) {
  final joined = digits.join();
  if (joined.length <= 3) {
    return joined;
  }
  final midpoint = joined.length ~/ 2;
  return '${joined.substring(0, midpoint)} ${joined.substring(midpoint)}';
}
