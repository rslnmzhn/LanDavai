import 'package:flutter_test/flutter_test.dart';
import 'package:landa/features/nearby_transfer/application/nearby_transfer_handshake_service.dart';

void main() {
  test('createVerificationCode returns six unique digits', () {
    final service = NearbyTransferHandshakeService();

    final sequence = service.createVerificationCode();

    expect(sequence, hasLength(6));
    expect(sequence.toSet(), hasLength(6));
    expect(sequence.every((digit) => RegExp(r'^\d$').hasMatch(digit)), isTrue);
  });

  test('buildChallenge includes exactly one valid answer', () {
    final service = NearbyTransferHandshakeService();
    const expected = <String>['1', '2', '3', '4', '5', '6'];

    final challenge = service.buildChallenge(expected);

    expect(challenge.choices, hasLength(3));
    expect(
      challenge.choices.where(
        (choice) => service.isValidChoice(
          expectedCode: expected,
          selectedChoice: choice,
        ),
      ),
      hasLength(1),
    );
  });
}
