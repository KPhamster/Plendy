import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Enum for auto-scan mode preference
enum AutoScanMode { quickScan, deepScan }

/// Service to manage AI-related user settings.
/// Notifies listeners when settings change.
class AiSettingsService extends ChangeNotifier {
  static const String aiUseManual = 'manual';
  static const String aiUseSemiAuto = 'semi_auto';

  static const String _aiUseKey = 'ai_use_option';
  static const String _autoExtractLocationsKey = 'ai_auto_extract_locations';
  static const String _autoSetCategoriesKey = 'ai_auto_set_categories';
  static const String _autoScanModeKey = 'ai_auto_scan_mode';

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
  AutoScanMode _autoScanMode = AutoScanMode.quickScan;

  Future<SharedPreferences> _getPrefs() async {
    _prefs ??= await SharedPreferences.getInstance();
    return _prefs!;
  }

  Future<void> _load() async {
    final prefs = await _getPrefs();
    _aiUseOption = prefs.getString(_aiUseKey) ?? aiUseSemiAuto;
    _autoExtractLocations = prefs.getBool(_autoExtractLocationsKey) ?? true;
    _autoSetCategories = prefs.getBool(_autoSetCategoriesKey) ?? true;
    final scanModeStr = prefs.getString(_autoScanModeKey);
    _autoScanMode = scanModeStr == 'deepScan' 
        ? AutoScanMode.deepScan 
        : AutoScanMode.quickScan;
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
    return _autoExtractLocations;
  }

  Future<bool> shouldAutoExtractLocations() async {
    if (!_isLoaded) {
      await _load();
    }
    return _autoExtractLocations;
  }

  bool shouldAutoSetCategoriesSync() {
    return _autoSetCategories;
  }

  Future<bool> shouldAutoSetCategories() async {
    if (!_isLoaded) {
      await _load();
    }
    return _autoSetCategories;
  }

  Future<AutoScanMode> getAutoScanMode() async {
    if (!_isLoaded) {
      await _load();
    }
    return _autoScanMode;
  }

  AutoScanMode getAutoScanModeSync() {
    return _autoScanMode;
  }

  Future<void> setAutoScanMode(AutoScanMode mode) async {
    final prefs = await _getPrefs();
    final modeStr = mode == AutoScanMode.deepScan ? 'deepScan' : 'quickScan';
    await prefs.setString(_autoScanModeKey, modeStr);
    _autoScanMode = mode;
    _isLoaded = true;
    notifyListeners();
  }

  Future<bool> shouldUseDeepScan() async {
    if (!_isLoaded) {
      await _load();
    }
    return _autoScanMode == AutoScanMode.deepScan;
  }
}
