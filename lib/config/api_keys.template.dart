import 'dart:io';
import 'package:flutter/foundation.dart' show kIsWeb;

/// Centralized class for API keys used throughout the app
/// 
/// TO USE: Copy this file to api_keys.dart and replace placeholder values with your actual API keys
class ApiKeys {
  // Google Maps API keys for different platforms
  static String get googleMapsApiKey {
    if (kIsWeb) {
      return 'YOUR_BROWSER_API_KEY';
    } else if (Platform.isAndroid) {
      return 'YOUR_ANDROID_API_KEY';
    } else if (Platform.isIOS) {
      return 'YOUR_IOS_API_KEY';
    } else {
      return 'YOUR_DEFAULT_API_KEY';
    }
  }
  
  // Add other API keys as needed
}
