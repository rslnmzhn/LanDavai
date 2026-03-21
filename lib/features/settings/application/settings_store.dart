import 'package:flutter/foundation.dart';

import '../data/app_settings_repository.dart';
import '../domain/app_settings.dart';

class SettingsStore extends ChangeNotifier {
  SettingsStore({required AppSettingsRepository appSettingsRepository})
    : _appSettingsRepository = appSettingsRepository;

  final AppSettingsRepository _appSettingsRepository;

  AppSettings _settings = AppSettings.defaults;

  AppSettings get settings => _settings;

  Future<void> load() async {
    _settings = await _appSettingsRepository.load();
    notifyListeners();
  }

  Future<void> save(AppSettings settings) async {
    await _appSettingsRepository.save(settings);
    _settings = settings;
    notifyListeners();
  }
}
