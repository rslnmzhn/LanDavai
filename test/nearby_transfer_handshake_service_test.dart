import 'package:flutter_test/flutter_test.dart';
import 'package:landa/features/nearby_transfer/application/nearby_transfer_handshake_service.dart';

void main() {
  test('createEmojiSequence returns five unique emoji', () {
    final service = NearbyTransferHandshakeService();

    final sequence = service.createEmojiSequence();

    expect(sequence, hasLength(5));
    expect(sequence.toSet(), hasLength(5));
  });

  test('buildChallenge includes exactly one valid answer', () {
    final service = NearbyTransferHandshakeService();
    const expected = <String>['😀', '😎', '🤖', '🚀', '🌈'];

    final challenge = service.buildChallenge(expected);

    expect(challenge.choices, hasLength(3));
    expect(
      challenge.choices.where(
        (choice) => service.isValidChoice(
          expectedSequence: expected,
          selectedChoice: choice,
        ),
      ),
      hasLength(1),
    );
  });
}
