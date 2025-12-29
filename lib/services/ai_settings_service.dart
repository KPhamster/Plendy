import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Service to manage AI-related user settings.
/// Notifies listeners when settings change.
class AiSettingsService extends ChangeNotifier {
  static const String aiUseManual = 'manual';
  static const String aiUseSemiAuto = 'semi_auto';

  static const String _aiUseKey = 'ai_use_option';
  static const String _autoExtractLocationsKey = 'ai_auto_extract_locations';
  static const String _autoSetCategoriesKey = 'ai_auto_set_categories';

  static AiSettingsService? _instance;
  static AiSettingsService get instance {
    _instance ??= AiSettingsService._();
    return _instance!;
  }

  AiSettingsService._();

  SharedPreferences? _prefs;
  bool _isLoaded = false;

  String _aiUseOption = aiUseSemiAuto;
  bool _autoExtractLocations = true;
  bool _autoSetCategories = true;

  Future<SharedPreferences> _getPrefs() async {
    _prefs ??= await SharedPreferences.getInstance();
    return _prefs!;
  }

  Future<void> _load() async {
    final prefs = await _getPrefs();
    _aiUseOption = prefs.getString(_aiUseKey) ?? aiUseSemiAuto;
    _autoExtractLocations = prefs.getBool(_autoExtractLocationsKey) ?? true;
    _autoSetCategories = prefs.getBool(_autoSetCategoriesKey) ?? true;
    _isLoaded = true;
  }

  Future<void> preload() async {
    await _load();
  }

  Future<String> getAiUseOption() async {
    if (!_isLoaded) {
      await _load();
    }
    return _aiUseOption;
  }

  Future<bool> getAutoExtractLocations() async {
    if (!_isLoaded) {
      await _load();
    }
    return _autoExtractLocations;
  }

  Future<bool> getAutoSetCategories() async {
    if (!_isLoaded) {
      await _load();
    }
    return _autoSetCategories;
  }

  Future<void> setAiUseOption(String option) async {
    final prefs = await _getPrefs();
    await prefs.setString(_aiUseKey, option);
    _aiUseOption = option;
    _isLoaded = true;
    notifyListeners();
  }

  Future<void> setAutoExtractLocations(bool value) async {
    final prefs = await _getPrefs();
    await prefs.setBool(_autoExtractLocationsKey, value);
    _autoExtractLocations = value;
    _isLoaded = true;
    notifyListeners();
  }

  Future<void> setAutoSetCategories(bool value) async {
    final prefs = await _getPrefs();
    await prefs.setBool(_autoSetCategoriesKey, value);
    _autoSetCategories = value;
    _isLoaded = true;
    notifyListeners();
  }

  bool shouldAutoExtractLocationsSync() {
    return _aiUseOption == aiUseSemiAuto && _autoExtractLocations;
  }

  Future<bool> shouldAutoExtractLocations() async {
    if (!_isLoaded) {
      await _load();
    }
    return shouldAutoExtractLocationsSync();
  }
}
