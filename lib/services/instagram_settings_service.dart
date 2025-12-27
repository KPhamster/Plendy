import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Service to manage Instagram display settings
/// Notifies listeners when settings change
class InstagramSettingsService extends ChangeNotifier {
  static const String _instagramDisplayKey = 'instagram_display_option';
  
  static InstagramSettingsService? _instance;
  static InstagramSettingsService get instance {
    _instance ??= InstagramSettingsService._();
    return _instance!;
  }
  
  InstagramSettingsService._();
  
  SharedPreferences? _prefs;
  String _currentOption = 'default';
  
  Future<SharedPreferences> _getPrefs() async {
    _prefs ??= await SharedPreferences.getInstance();
    return _prefs!;
  }
  
  /// Get the current Instagram display option
  /// Returns 'default' for oEmbed HTML, 'webview' for Direct WebView
  Future<String> getDisplayOption() async {
    final prefs = await _getPrefs();
    _currentOption = prefs.getString(_instagramDisplayKey) ?? 'default';
    return _currentOption;
  }
  
  /// Set the Instagram display option
  /// 'default' = oEmbed HTML approach (no login required)
  /// 'webview' = Direct WebView approach (may require login)
  Future<void> setDisplayOption(String option) async {
    final prefs = await _getPrefs();
    await prefs.setString(_instagramDisplayKey, option);
    _currentOption = option;
    // Notify all listeners that settings changed
    notifyListeners();
  }
  
  /// Check if using direct WebView mode
  Future<bool> isWebViewMode() async {
    final option = await getDisplayOption();
    return option == 'webview';
  }
  
  /// Synchronous check - use only after ensuring prefs are loaded
  bool isWebViewModeSync() {
    return _currentOption == 'webview';
  }
  
  /// Preload preferences for synchronous access
  Future<void> preload() async {
    await getDisplayOption();
  }
}
