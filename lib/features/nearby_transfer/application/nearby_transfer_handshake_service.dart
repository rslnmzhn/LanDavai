import 'dart:math';

class NearbyTransferHandshakeChallenge {
  const NearbyTransferHandshakeChallenge({required this.choices});

  final List<List<String>> choices;
}

class NearbyTransferHandshakeService {
  NearbyTransferHandshakeService({Random? random})
    : _random = random ?? Random();

  final Random _random;

  static const List<String> _emojiPool = <String>[
    '😀',
    '😎',
    '🤖',
    '🛰️',
    '🚀',
    '🌈',
    '🍀',
    '🔥',
    '🎯',
    '🧩',
    '🌙',
    '⚡',
    '🐳',
    '🦊',
    '🍉',
    '🎧',
    '📦',
    '🔒',
    '🌊',
    '🪐',
    '🎲',
    '🫧',
    '🌻',
    '☁️',
  ];

  List<String> createEmojiSequence() {
    final pool = List<String>.from(_emojiPool);
    pool.shuffle(_random);
    return List<String>.unmodifiable(pool.take(5));
  }

  NearbyTransferHandshakeChallenge buildChallenge(
    List<String> correctSequence,
  ) {
    final normalizedCorrect = List<String>.unmodifiable(correctSequence);
    final choices = <List<String>>[normalizedCorrect];
    while (choices.length < 3) {
      final candidate = createEmojiSequence();
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
    required List<String> expectedSequence,
    required List<String> selectedChoice,
  }) {
    return _sameSequence(expectedSequence, selectedChoice);
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
