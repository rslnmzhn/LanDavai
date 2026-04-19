import 'package:flutter_test/flutter_test.dart';
import 'package:landa/features/nearby_transfer/application/nearby_transfer_handshake_service.dart';

void main() {
  test('createVerificationCode returns a 2-digit code', () {
    final service = NearbyTransferHandshakeService();

    final sequence = service.createVerificationCode();

    expect(sequence, hasLength(2));
    expect(sequence.every((digit) => RegExp(r'^\d$').hasMatch(digit)), isTrue);
  });

  test('sanitizeCodeInput keeps only the first two digits', () {
    final service = NearbyTransferHandshakeService();

    expect(service.sanitizeCodeInput('12'), '12');
    expect(service.sanitizeCodeInput('1a2'), '12');
    expect(service.sanitizeCodeInput(' 9-87 '), '98');
  });

  test('isValidCode compares entered code against the expected 2 digits', () {
    final service = NearbyTransferHandshakeService();

    expect(
      service.isValidCode(
        expectedCode: const <String>['1', '2'],
        enteredCode: '12',
      ),
      isTrue,
    );
    expect(
      service.isValidCode(
        expectedCode: const <String>['1', '2'],
        enteredCode: '21',
      ),
      isFalse,
    );
  });

  test('expiry and cooldown helpers honor the injected clock', () {
    var now = DateTime(2026, 1, 1, 10, 0, 0);
    final service = NearbyTransferHandshakeService(
      now: () => now,
      codeLifetime: const Duration(seconds: 5),
      cooldownDuration: const Duration(seconds: 7),
    );

    final expiresAt = service.createExpiryTime();
    final cooldownUntil = service.createCooldownUntil();

    expect(service.isExpired(expiresAt), isFalse);
    expect(service.isCoolingDown(cooldownUntil), isTrue);

    now = now.add(const Duration(seconds: 6));
    expect(service.isExpired(expiresAt), isTrue);
    expect(service.isCoolingDown(cooldownUntil), isTrue);
    expect(service.remainingCooldownSeconds(cooldownUntil), greaterThan(0));

    now = now.add(const Duration(seconds: 2));
    expect(service.isCoolingDown(cooldownUntil), isFalse);
    expect(service.remainingCooldownSeconds(cooldownUntil), 0);
  });
}
