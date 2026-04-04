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
            'Попросите второе устройство подтвердить этот набор эмодзи:',
            style: Theme.of(context).textTheme.titleSmall,
          ),
          const SizedBox(height: AppSpacing.sm),
          Text(
            store.emojiSequence.join(' '),
            style: Theme.of(context).textTheme.headlineSmall,
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
          'Выберите совпадающий набор эмодзи',
          style: Theme.of(context).textTheme.titleSmall,
        ),
        const SizedBox(height: AppSpacing.sm),
        for (final choice in challenge.choices) ...[
          SizedBox(
            width: double.infinity,
            child: OutlinedButton(
              onPressed: () => store.selectHandshakeChoice(choice),
              child: Text(choice.join(' ')),
            ),
          ),
          const SizedBox(height: AppSpacing.xs),
        ],
      ],
    );
  }
}
