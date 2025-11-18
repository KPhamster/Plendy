import 'dart:convert';
import 'dart:io';
import 'package:flutter/services.dart';
import 'package:crypto/crypto.dart';

/// Service to interact with Google Play Integrity API
/// 
/// This service provides methods to request integrity tokens from Google Play
/// to verify that your app is running on a genuine device with Google Play Services.
/// 
/// Reference: https://developer.android.com/google/play/integrity/setup
class PlayIntegrityService {
  static const MethodChannel _channel =
      MethodChannel('com.plendy.app/play_integrity');

  /// Requests a classic integrity token
  /// 
  /// Classic requests are one-time requests that provide immediate results.
  /// They're suitable for one-off integrity checks.
  /// 
  /// [nonce] - A unique value to prevent replay attacks. Should be different for each request.
  /// 
  /// Returns a Map containing:
  /// - 'token': The integrity token (String)
  /// - 'type': The token type ('classic')
  /// 
  /// Throws [PlatformException] if the request fails.
  /// 
  /// Example:
  /// ```dart
  /// final result = await PlayIntegrityService.requestClassicIntegrityToken('my-unique-nonce');
  /// final token = result['token'];
  /// // Send token to your backend for verification
  /// ```
  static Future<Map<String, dynamic>> requestClassicIntegrityToken(
      String nonce) async {
    if (!Platform.isAndroid) {
      throw UnsupportedError('Play Integrity API is only available on Android');
    }

    try {
      // Hash the nonce using SHA-256
      final requestHash = _generateRequestHash(nonce);

      final result = await _channel.invokeMethod('requestIntegrityToken', {
        'requestHash': requestHash,
      });

      return Map<String, dynamic>.from(result);
    } on PlatformException catch (e) {
      throw PlayIntegrityException(
        code: e.code,
        message: e.message ?? 'Unknown error',
        details: e.details,
      );
    }
  }

  /// Prepares a standard integrity token provider
  /// 
  /// Standard requests are more efficient for frequent integrity checks.
  /// Call this method once during app initialization, then use
  /// [requestStandardIntegrityToken] for subsequent requests.
  /// 
  /// Returns a Map containing:
  /// - 'success': true if preparation was successful
  /// - 'message': Status message
  /// 
  /// Throws [PlatformException] if preparation fails.
  /// 
  /// Example:
  /// ```dart
  /// await PlayIntegrityService.prepareStandardIntegrityToken();
  /// // Now you can make standard requests
  /// ```
  static Future<Map<String, dynamic>> prepareStandardIntegrityToken() async {
    if (!Platform.isAndroid) {
      throw UnsupportedError('Play Integrity API is only available on Android');
    }

    try {
      final result =
          await _channel.invokeMethod('prepareStandardIntegrityToken');
      return Map<String, dynamic>.from(result);
    } on PlatformException catch (e) {
      throw PlayIntegrityException(
        code: e.code,
        message: e.message ?? 'Unknown error',
        details: e.details,
      );
    }
  }

  /// Requests a standard integrity token
  /// 
  /// Must call [prepareStandardIntegrityToken] first before using this method.
  /// Standard requests are more efficient for frequent integrity checks.
  /// 
  /// [nonce] - A unique value to prevent replay attacks. Should be different for each request.
  /// 
  /// Returns a Map containing:
  /// - 'token': The integrity token (String)
  /// - 'type': The token type ('standard')
  /// 
  /// Throws [PlatformException] if the request fails or if the token provider
  /// hasn't been prepared.
  /// 
  /// Example:
  /// ```dart
  /// // First, prepare the token provider
  /// await PlayIntegrityService.prepareStandardIntegrityToken();
  /// 
  /// // Then make standard requests
  /// final result = await PlayIntegrityService.requestStandardIntegrityToken('my-unique-nonce');
  /// final token = result['token'];
  /// // Send token to your backend for verification
  /// ```
  static Future<Map<String, dynamic>> requestStandardIntegrityToken(
      String nonce) async {
    if (!Platform.isAndroid) {
      throw UnsupportedError('Play Integrity API is only available on Android');
    }

    try {
      // Hash the nonce using SHA-256
      final requestHash = _generateRequestHash(nonce);

      final result =
          await _channel.invokeMethod('requestStandardIntegrityToken', {
        'requestHash': requestHash,
      });

      return Map<String, dynamic>.from(result);
    } on PlatformException catch (e) {
      throw PlayIntegrityException(
        code: e.code,
        message: e.message ?? 'Unknown error',
        details: e.details,
      );
    }
  }

  /// Generates a SHA-256 hash from the nonce
  static String _generateRequestHash(String nonce) {
    final bytes = utf8.encode(nonce);
    final digest = sha256.convert(bytes);
    return digest.toString();
  }

  /// Helper method to generate a unique nonce
  /// 
  /// Generates a nonce using the current timestamp and a random component.
  /// You can customize this to fit your security requirements.
  /// 
  /// Returns a unique String that can be used as a nonce.
  /// 
  /// Example:
  /// ```dart
  /// final nonce = PlayIntegrityService.generateNonce();
  /// final result = await PlayIntegrityService.requestClassicIntegrityToken(nonce);
  /// ```
  static String generateNonce() {
    final timestamp = DateTime.now().millisecondsSinceEpoch;
    final random = DateTime.now().microsecond;
    return '$timestamp-$random';
  }
}

/// Exception thrown when Play Integrity API operations fail
class PlayIntegrityException implements Exception {
  final String code;
  final String message;
  final dynamic details;

  PlayIntegrityException({
    required this.code,
    required this.message,
    this.details,
  });

  @override
  String toString() {
    return 'PlayIntegrityException: [$code] $message${details != null ? '\nDetails: $details' : ''}';
  }
}

