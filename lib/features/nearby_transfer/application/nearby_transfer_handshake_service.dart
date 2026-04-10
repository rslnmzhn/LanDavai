import 'dart:math';

class NearbyTransferHandshakeChallenge {
  const NearbyTransferHandshakeChallenge({required this.choices});

  final List<List<String>> choices;
}

class NearbyTransferHandshakeService {
  NearbyTransferHandshakeService({Random? random})
    : _random = random ?? Random();

  final Random _random;

  static const List<String> _digitPool = <String>[
    '0',
    '1',
    '2',
    '3',
    '4',
    '5',
    '6',
    '7',
    '8',
    '9',
  ];

  List<String> createVerificationCode() {
    final pool = List<String>.from(_digitPool);
    pool.shuffle(_random);
    return List<String>.unmodifiable(pool.take(6));
  }

  NearbyTransferHandshakeChallenge buildChallenge(List<String> correctCode) {
    final normalizedCorrect = List<String>.unmodifiable(correctCode);
    final choices = <List<String>>[normalizedCorrect];
    while (choices.length < 3) {
      final candidate = createVerificationCode();
      if (_sameSequence(candidate, normalizedCorrect)) {
        continue;
      }
      if (choices.any((choice) => _sameSequence(choice, candidate))) {
        continue;
      }
      choices.add(candidate);
    }
    choices.shuffle(_random);
    return NearbyTransferHandshakeChallenge(
      choices: List<List<String>>.unmodifiable(
        choices.map(List<String>.unmodifiable),
      ),
    );
  }

  bool isValidChoice({
    required List<String> expectedCode,
    required List<String> selectedChoice,
  }) {
    return _sameSequence(expectedCode, selectedChoice);
  }

  bool _sameSequence(List<String> left, List<String> right) {
    if (left.length != right.length) {
      return false;
    }
    for (var index = 0; index < left.length; index += 1) {
      if (left[index] != right[index]) {
        return false;
      }
    }
    return true;
  }
}
