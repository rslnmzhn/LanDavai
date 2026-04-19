import 'dart:math';

class NearbyTransferHandshakeService {
  NearbyTransferHandshakeService({
    Random? random,
    DateTime Function()? now,
    this.codeLifetime = const Duration(seconds: 30),
    this.cooldownDuration = const Duration(seconds: 10),
    this.maxAttemptsBeforeCooldown = 3,
  }) : _random = random ?? Random(),
       _now = now ?? DateTime.now;

  final Random _random;
  final DateTime Function() _now;
  final Duration codeLifetime;
  final Duration cooldownDuration;
  final int maxAttemptsBeforeCooldown;

  List<String> createVerificationCode() {
    return List<String>.unmodifiable(<String>[
      _random.nextInt(10).toString(),
      _random.nextInt(10).toString(),
    ]);
  }

  DateTime createExpiryTime() => _now().add(codeLifetime);

  DateTime createCooldownUntil() => _now().add(cooldownDuration);

  DateTime now() => _now();

  bool isExpired(DateTime? expiresAt) {
    if (expiresAt == null) {
      return false;
    }
    return !_now().isBefore(expiresAt);
  }

  bool isCoolingDown(DateTime? cooldownUntil) {
    if (cooldownUntil == null) {
      return false;
    }
    return _now().isBefore(cooldownUntil);
  }

  int remainingCooldownSeconds(DateTime? cooldownUntil) {
    if (!isCoolingDown(cooldownUntil)) {
      return 0;
    }
    return cooldownUntil!.difference(_now()).inSeconds + 1;
  }

  bool isValidCode({
    required List<String> expectedCode,
    required String enteredCode,
  }) {
    return expectedCode.join() == sanitizeCodeInput(enteredCode);
  }

  String sanitizeCodeInput(String rawInput) {
    final digitsOnly = rawInput.replaceAll(RegExp(r'\D'), '');
    if (digitsOnly.length <= 2) {
      return digitsOnly;
    }
    return digitsOnly.substring(0, 2);
  }
}
