import 'package:flutter/foundation.dart';

import '../data/configured_discovery_targets_repository.dart';

class ConfiguredDiscoveryTargetsStore extends ChangeNotifier {
  ConfiguredDiscoveryTargetsStore({
    required ConfiguredDiscoveryTargetsRepository repository,
  }) : _repository = repository,
       _persistChanges = true;

  ConfiguredDiscoveryTargetsStore.inMemory()
    : _repository = ConfiguredDiscoveryTargetsRepository.withDatabaseProvider(
        databaseProvider: () async {
          throw UnsupportedError(
            'ConfiguredDiscoveryTargetsStore.inMemory() does not persist.',
          );
        },
      ),
      _persistChanges = false;

  final ConfiguredDiscoveryTargetsRepository _repository;
  final bool _persistChanges;

  List<String> _targets = const <String>[];

  List<String> get targets => List<String>.unmodifiable(_targets);

  Set<String> get targetSet => Set<String>.unmodifiable(_targets.toSet());

  bool containsIp(String ip) {
    final normalized =
        ConfiguredDiscoveryTargetsRepository.normalizeIpv4(ip) ?? ip.trim();
    return _targets.contains(normalized);
  }

  Future<void> load() async {
    if (!_persistChanges) {
      return;
    }
    _targets = await _repository.load();
    notifyListeners();
  }

  String? validationErrorFor(String raw) {
    final trimmed = raw.trim();
    if (trimmed.isEmpty) {
      return 'Введите IPv4-адрес.';
    }
    final normalized = ConfiguredDiscoveryTargetsRepository.normalizeIpv4(
      trimmed,
    );
    if (normalized == null) {
      return 'Введите корректный IPv4-адрес.';
    }
    if (_targets.contains(normalized)) {
      return 'Этот адрес уже добавлен.';
    }
    return null;
  }

  Future<bool> addTarget(String raw) async {
    final error = validationErrorFor(raw);
    if (error != null) {
      return false;
    }
    final normalized = ConfiguredDiscoveryTargetsRepository.normalizeIpv4(raw)!;
    final nextTargets = <String>[..._targets, normalized]..sort(_compareIp);
    await _replaceTargets(nextTargets);
    return true;
  }

  Future<void> removeTarget(String ip) async {
    final normalized =
        ConfiguredDiscoveryTargetsRepository.normalizeIpv4(ip) ?? ip.trim();
    final nextTargets = _targets
        .where((target) => target != normalized)
        .toList(growable: false);
    if (listEquals(nextTargets, _targets)) {
      return;
    }
    await _replaceTargets(nextTargets);
  }

  Future<void> _replaceTargets(List<String> nextTargets) async {
    if (_persistChanges) {
      await _repository.save(nextTargets);
    }
    _targets = List<String>.unmodifiable(nextTargets);
    notifyListeners();
  }

  static int _compareIp(String a, String b) {
    final aParts = a.split('.').map(int.parse).toList(growable: false);
    final bParts = b.split('.').map(int.parse).toList(growable: false);
    for (var index = 0; index < 4; index += 1) {
      final compare = aParts[index].compareTo(bParts[index]);
      if (compare != 0) {
        return compare;
      }
    }
    return 0;
  }
}
